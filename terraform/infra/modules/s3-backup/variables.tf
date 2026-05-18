variable "project_name" {
  description = "Short project identifier used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "glacier_transition_days" {
  description = "Days after which daily Gitea dumps move to Glacier."
  type        = number
  default     = 30
}

variable "expiration_days" {
  description = "Days after which Gitea dumps are deleted."
  type        = number
  default     = 365
}
