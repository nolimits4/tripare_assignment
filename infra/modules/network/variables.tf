variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. hotelapp-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be between 2 and 3 to keep the ALB and RDS multi-AZ capable."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway (cheap, dev) instead of one per AZ (resilient, prod)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
