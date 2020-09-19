provider "aws" {
  region  = "ap-south-1"
  profile = "default"
}

//Key 1
resource "tls_private_key" "wpkey" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}
resource "aws_key_pair" "w_generated_key" {
  key_name   = "wpkey"
  public_key = tls_private_key.wpkey.public_key_openssh
}
resource "local_file" "w_key_file" {
  content         = tls_private_key.wpkey.private_key_pem
  filename        = "wpkey.pem"
  file_permission = 0400
}
//Key2
resource "tls_private_key" "bastionkey" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}
resource "aws_key_pair" "b_generated_key" {
  key_name   = "bastionkey"
  public_key = tls_private_key.bastionkey.public_key_openssh
}
resource "local_file" "b_key_file" {
  content         = tls_private_key.bastionkey.private_key_pem
  filename        = "bastionkey.pem"
  file_permission = 0400
}

//Key3
resource "tls_private_key" "mysqlkey" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}
resource "aws_key_pair" "m_generated_key" {
  key_name   = "mysqlkey"
  public_key = tls_private_key.mysqlkey.public_key_openssh
}
resource "local_file" "m_key_file" {
  content         = tls_private_key.mysqlkey.private_key_pem
  filename        = "mysqlkey.pem"
  file_permission = 0400
}


resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public subnet"
  }

}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"
  tags = {
    Name = "private subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}


// Route tables - public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.myvpc.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Route Table"
  }
}
resource "aws_route_table_association" "public_rt_association" {

  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id

}
// Route tables - private subnet
resource "aws_route_table" "private_rt" {
  vpc_id = "${aws_vpc.myvpc.id}"

  route {
    cidr_block  = "0.0.0.0/0"
    instance_id = "${aws_instance.bastion.id}"
  }
}

resource "aws_route_table_association" "private_rt_association" {
  subnet_id      = "${aws_subnet.private_subnet.id}"
  route_table_id = "${aws_route_table.private_rt.id}"
}

// Security Groups
resource "aws_security_group" "wordpress_sg" {
  vpc_id = aws_vpc.myvpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.private_subnet.cidr_block]
  }
}

resource "aws_security_group" "mysql_sg" {
  vpc_id = aws_vpc.myvpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.myvpc.cidr_block]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["${aws_instance.bastion.private_ip}/32"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [aws_vpc.myvpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = [aws_instance.bastion]
}

/*resource "aws_security_group" "bastion_sg" {
  name   = "bastion-security-group"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [aws_subnet.private_subnet.cidr_block]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [aws_subnet.private_subnet.cidr_block]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}*/
resource "aws_security_group" "bastion_sg" {
  name   = "bastion-security-group"
  vpc_id = aws_vpc.myvpc.id
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "wordpress" {
  ami                         = "ami-000cbce3e1b899ebd" //bitnami wordpress
  instance_type               = "t2.micro"
  key_name                    = "wpkey"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.wordpress_sg.id]
  associate_public_ip_address = true


  /*connection {
    type        = "ssh"
    user        = "bitnami"
    private_key = tls_private_key.wpkey.private_key_pem
    host        = aws_instance.wordpress.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "cd /opt/bitnami/apps/wordpress/htdocs/",
      "sed -i "s/define('DB_NAME', '.*');/define('DB_NAME', 'wordpress');/" wp-config.php",
      "sed -i "s/define('DB_USER', '.*');/define('DB_USER', 'wordpress');/" wp-config.php",
      "sed -i "s/define('DB_PASSWORD', '.*');/define('DB_PASSWORD', 'wordpress');/" wp-config.php",
      "sudo reboot"
    ]
  }
   */

  depends_on = [aws_instance.bastion]
  tags = {
    Name = "V_wordpress"
  }
}

resource "aws_instance" "mysql" {
  ami                    = "ami-0019ac6129392a0f2" //bitnami mysql
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet.id
  key_name               = "mysqlkey"
  vpc_security_group_ids = [aws_security_group.mysql_sg.id, aws_security_group.bastion_sg.id]

  tags = {
    Name = "V_mysql"
  }

  depends_on = [aws_instance.bastion]
}


resource "aws_instance" "bastion" {
  ami                    = "ami-00b3aa8a93dd09c13" //aws - vpc - bastion or you can choose Linux 2 also
  instance_type          = "t2.micro"
  key_name               = "bastionkey"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "V_bastion"
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  vpc      = true
}
