variable "aws_region" {
  default = "eu-west-2"
}


variable "instance_tenancy" {
  description = "tenancy option for instances launched into the vpc"
  default     = "default"
  type        = string
}

variable "enable_dns_hostname" {
  description = "should be tru to enable DNS support in the vpc"
  default     = true
  type        = bool
}


variable "enable_dns_support" {
  description = "should be tru to enable DNS support in the vpc"
  default     = true
  type        = bool
}


variable "environment" {
  default = "Demo"
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "CIDR block of the vpc"
}

variable "public_subnets_cidr" {
  type        = list(any)
  default     = ["10.0.0.0/20", "10.0.128.0/20"]
  description = "CIDR block for Public Subnet"
}

variable "private_subnets_cidr" {
  type        = list(any)
  default     = ["10.0.16.0/20", "10.0.144.0/20"]
  description = "CIDR block for Private Subnet"
}


variable "availability_zones" {
 type        = list(string)
 description = "Availability Zones"
 default     = ["eu-west-2a", "eu-west-2b",]
}