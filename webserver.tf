variable "region" {}
variable "profile" {}
variable "availability_zone" {}
variable "key_name" {}

provider "aws" {
  profile = var.profile
  region  = var.region
}

//Default vpc
resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}
resource "aws_default_subnet" "default_az1" {
  availability_zone = var.availability_zone

  tags = {
    Name = "Default subnet for ap-south-1a"
  }
}


//Creating key 
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits = "4096"
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.key.public_key_openssh

}

resource "local_file" "key_file" {
  content         = tls_private_key.key.private_key_pem
  filename        = "${var.key_name}.pem"
  file_permission = 0400
}

//Security group
resource "aws_security_group" "sg1" {
  vpc_id = aws_default_vpc.default.id
  name   = "allow_ssh_http"
  
  lifecycle {
    create_before_destroy = true
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}




resource "aws_instance" "web_ec2" {

  ami                    = "ami-0447a12f28fddb066" //Linux 2 AMI[Free tier eligible]
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.generated_key.key_name
  availability_zone      = var.availability_zone
  subnet_id = aws_default_subnet.default_az1.id
  vpc_security_group_ids = [aws_security_group.sg1.id]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    host        = aws_instance.web_ec2.public_ip
    private_key = tls_private_key.key.private_key_pem
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd git -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
    ]
  }
  
  //depends_on=[aws_security_group.sg1]

  tags = {
    name = "webserver-ec2-instance"
  }
}

//Create ebs
resource "aws_ebs_volume" "ebs1" {
  size              = 1
  availability_zone = var.availability_zone
  encrypted         = true
}

//Attach ebs

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/xvdh"
  volume_id   = aws_ebs_volume.ebs1.id
  instance_id = aws_instance.web_ec2.id

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key.private_key_pem
    host        = aws_instance.web_ec2.public_ip

  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Vishnukvsvk/LW-TASK1.git /var/www/html"
    ]

  }
  
  //To destroy ebs, we need to unmount the ebs fro instance.
  provisioner "remote-exec" {
        when    = destroy
        inline  = [
            "sudo umount /var/www/html"
        ]
    }

  depends_on = [aws_instance.web_ec2]
}

//S3 bucket
resource "aws_s3_bucket" "bucket1" {
  bucket        = "task1-myimage"
  acl           = "public-read"
  force_destroy = true
}

resource "null_resource" "git_download" {
  provisioner "local-exec" {
    command = "git clone https://github.com/Vishnukvsvk/LW-TASK1.git Folder1"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rmdir  Folder1 /s /q" //rm -rf Folder1 --> for linuxos  2>nul
  }

}

resource "aws_s3_bucket_object" "image_upload" {
  key        = "image1.png"
  bucket     = aws_s3_bucket.bucket1.bucket
  source     = "Folder1/task1image.png"
  acl        = "public-read"
  content_type = "image/png"
  depends_on = [aws_s3_bucket.bucket1]
}

//Cloudfront
locals {
  s3_origin_id = "S3-task1-myimage"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  //Origin Settingd
  origin {
    domain_name = "${aws_s3_bucket.bucket1.bucket_domain_name}"
    origin_id   = "${local.s3_origin_id}"

  }

  enabled         = true
  is_ipv6_enabled = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"

  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
   
   depends_on = [aws_volume_attachment.ebs_att]

}

resource "null_resource" "update_link" {
    connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key.private_key_pem
    host        = aws_instance.web_ec2.public_ip
    port        = 22
  }

  provisioner "remote-exec" {
    inline = [
        "sudo chmod 777 /var/www/html -R",
        "sudo echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image_upload.key}'>\" >> /var/www/html/index.html",
    ]
  }
  depends_on = [aws_cloudfront_distribution.s3_distribution]
}





//Output values
output "vpc_" {
    value = aws_default_vpc.default.id
}
output "subnet_" {
    value = aws_default_subnet.default_az1.id
}
output "publicip_" {
  value = aws_instance.web_ec2.public_ip
}
output "ebs_" {
  value = aws_ebs_volume.ebs1.id
}
output "ec2_" {
  value = aws_instance.web_ec2.id
}
output "domainname_" {
  value = aws_s3_bucket.bucket1.bucket_domain_name
}