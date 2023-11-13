variable aws_profile {
  type        = string
  default     = "default"
  description = "AWS Profile"
}

variable aws_region {
  type        = string
  default     = "eu-west-1"
  description = "AWS Region"
}

variable aws_vpc_gw {
  type        = string
  description = "AWS Virtual Private Gateway ID"
}

variable gcp_project {
  type        = string
  description = "GCP Project ID"
}

variable gcp_region {
  type        = string
  default     = "europe-west1"
  description = "GCP Region"
}

variable gcp_vpc_name {
  type        = string
  description = "GCP VPC Name"
}
