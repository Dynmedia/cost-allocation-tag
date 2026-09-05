variable "cost_allocation_tag_keys" {
  description = "User-defined tag keys to activate as cost allocation tags."
  type        = list(string)
  default     = ["Owner", "Workload", "CostCenter", "Environment"]
}

variable "budget_name" {
  type    = string
  default = "amazon-q-agent-monthly-budget"
}

variable "budget_limit_amount" {
  description = "Monthly budget limit (string, e.g. \"500\")."
  type        = string
  default     = "500"
}

variable "budget_limit_unit" {
  type    = string
  default = "USD"
}

variable "cost_filter_tag_key" {
  type    = string
  default = "Workload"
}

variable "cost_filter_tag_value" {
  type    = string
  default = "amazon-q-agent"
}

variable "notify_emails" {
  description = "Email addresses that receive budget overrun alerts."
  type        = list(string)
  # No default on purpose - force the operator to supply a real address.
}

variable "actual_thresholds_percent" {
  type    = list(number)
  default = [80, 100]
}

variable "forecasted_thresholds_percent" {
  type    = list(number)
  default = [100]
}
