//configuração do ´provedor aws para a região us-east-1
provider "aws" {
  region = "us-east-1"
}

//definição de variaveis
variable "projeto" {
  description = "Nome do projeto"
  type        = string
  default     = "VExpenses"
}

//definição de variaveis
variable "candidato" {
  description = "Nome do candidato"
  type        = string
  default     = "SeuNome"
}

//"tls_private_key" = gera uma chave TLS privada. 
//o "algorithm chama a chave "RSA" que é uma chave de alto padrão de segurança.
//bits é um parametro que especifica o tamanho da chave RSA
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

// recurso que cria uma par de chaves para instancia EC2
//key_name: parametro que chama o nome do par de chaves
//public_key: definição de chave associada as chaves AWS
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "${var.projeto}-${var.candidato}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

//criação de rede para gerenciar uma infraestrutura
resource "aws_vpc" "main_vpc" {
  //definição de bloco que determina quantidade de intervalo que o Ip pode usar
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.projeto}-${var.candidato}-vpc"
  }
}

//cria uma sub rede na VPC
resource "aws_subnet" "main_subnet" {
  //local onde éc riada a sub rede
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.projeto}-${var.candidato}-subnet"
  }
}

//cria um gateway de internet para a VPC
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-igw"
  }
}

//cria uma tabela de rotas para vpc
resource "aws_route_table" "main_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table"
  }
}

//Associa a tabela de rotas criada anteriormente à sub-rede, garantindo que o +
//tráfego da sub-rede utilize essa tabela de rotas
resource "aws_route_table_association" "main_association" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.main_route_table.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table_association"
  }
}

//cria a segurança na VPC para auxiliar as instancias EC2
resource "aws_security_group" "main_sg" {
  name        = "${var.projeto}-${var.candidato}-sg"
  description = "Permitir SSH de um IP específico e tráfego HTTP/HTTPS"
  vpc_id      = aws_vpc.main_vpc.id

//Permitir acesso SSH apenas a um IP específico reduz a superfície de ataque. +
//Isso evita que qualquer pessoa na internet tenha acesso à instância, +
//limitando-o a um único endereço IP conhecido e autorizado
  # Regras de entrada
  ingress {
    description      = "Allow SSH from a specific IP"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] // limitar o acesso SSH ao ip especifico
    ipv6_cidr_blocks = ["::/0"]
  }

  # Regras de saída
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-sg"
  }
}

//Define um data source que busca a imagem do Amazon Machine Image
data "aws_ami" "debian12" {
  most_recent = true

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"]
}

// Cria uma instância EC2 usando a AMI do Debian
resource "aws_instance" "debian_ec2" {
  ami             = data.aws_ami.debian12.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.main_subnet.id
  key_name        = aws_key_pair.ec2_key_pair.key_name
  security_groups = [aws_security_group.main_sg.name]

  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get upgrade -y
              apt-get install -y nginx
              systemctl start nginx
              systemctl enable nginx
              EOF

  tags = {
    Name = "${var.projeto}-${var.candidato}-ec2"
  }
}

// fornece valores de saida para a aplicação
output "private_key" {
  description = "Chave privada para acessar a instância EC2"
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true
}

// fornece informações para a saida do IP da instancia EC2
output "ec2_public_ip" {
  description = "Endereço IP público da instância EC2"
  value       = aws_instance.debian_ec2.public_ip
}



