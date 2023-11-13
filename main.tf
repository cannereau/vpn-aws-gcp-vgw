# build random suffix
resource "random_id" "sfx" {
  byte_length = 4
}

# build random key
resource "random_password" "key" {
  length  = 48
  special = false
}

###################
#####   AWS   #####
###################

# vpn gateway
data "aws_vpn_gateway" "aws_vpn_gw" {
  id = var.aws_vpc_gw
}

# vpc
data "aws_vpc" "aws_vpc" {
  id = data.aws_vpn_gateway.aws_vpn_gw.attached_vpc_id
}

# customer gateway
resource "aws_customer_gateway" "aws_vpn_cg" {
  bgp_asn     = 65456
  device_name = "GCP Classic VPN"
  ip_address  = google_compute_address.gcp_vpn_ip.address
  type        = "ipsec.1"
  tags        = {
    Name = "cgw-gcp-${random_id.sfx.hex}"
  }
}

# vpn tunnel
resource "aws_vpn_connection" "aws_vpn_cnx" {
  vpn_gateway_id      = var.aws_vpc_gw
  customer_gateway_id = aws_customer_gateway.aws_vpn_cg.id
  type                = "ipsec.1"
  static_routes_only  = true
  tags                = {
    Name = "cnx-gcp-${random_id.sfx.hex}"
  }

  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_preshared_key                = random_password.key.result
  tunnel1_phase1_dh_group_numbers      = [2]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-512"]
  tunnel1_phase2_dh_group_numbers      = [2]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-512"]
}

# route vpn to gcp vpc
resource "aws_vpn_connection_route" "aws_vpn_routes" {
  for_each = data.google_compute_subnetwork.gcp_subnets

  destination_cidr_block = each.value.ip_cidr_range
  vpn_connection_id      = aws_vpn_connection.aws_vpn_cnx.id
}

###################
#####   GCP   #####
###################

# vpc
data "google_compute_network" "gcp_vpc" {
  name   = var.gcp_vpc_name
}

# subnets
data "google_compute_subnetwork" "gcp_subnets" {
  for_each  = toset(data.google_compute_network.gcp_vpc.subnetworks_self_links)

  self_link = each.key
}

# vpn gateway
resource "google_compute_vpn_gateway" "gcp_vpn_gw" {
  name    = "vpn-aws-${random_id.sfx.hex}"
  network = data.google_compute_network.gcp_vpc.id
}

# static public ip
resource "google_compute_address" "gcp_vpn_ip" {
  name = "ip-aws-${random_id.sfx.hex}"
}

# forwarding rules for IPSEC
resource "google_compute_forwarding_rule" "gcp_fwr_esp" {
  name        = "fwr-aws-esp-${random_id.sfx.hex}"
  ip_protocol = "ESP"
  ip_address  = google_compute_address.gcp_vpn_ip.address
  target      = google_compute_vpn_gateway.gcp_vpn_gw.id
}
resource "google_compute_forwarding_rule" "gcp_fwr_udp500" {
  name        = "fwr-aws-udp500-${random_id.sfx.hex}"
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = google_compute_address.gcp_vpn_ip.address
  target      = google_compute_vpn_gateway.gcp_vpn_gw.id
}
resource "google_compute_forwarding_rule" "gcp_fwr_udp4500" {
  name        = "fwr-aws-udp4500-${random_id.sfx.hex}"
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = google_compute_address.gcp_vpn_ip.address
  target      = google_compute_vpn_gateway.gcp_vpn_gw.id
}

# vpn tunnel
resource "google_compute_vpn_tunnel" "gcp_vpn_cnx" {
  name          = "cnx-aws-${random_id.sfx.hex}"
  ike_version   = 2
  peer_ip       = aws_vpn_connection.aws_vpn_cnx.tunnel1_address
  shared_secret = random_password.key.result

  local_traffic_selector  = ["0.0.0.0/0"]
  remote_traffic_selector = ["0.0.0.0/0"]
  target_vpn_gateway      = google_compute_vpn_gateway.gcp_vpn_gw.id

  depends_on = [
    google_compute_forwarding_rule.gcp_fwr_esp,
    google_compute_forwarding_rule.gcp_fwr_udp500,
    google_compute_forwarding_rule.gcp_fwr_udp4500,
  ]
}

# route to aws vpc
resource "google_compute_route" "gcp_vpn_rt" {
  name       = "rt-aws-${random_id.sfx.hex}"
  network    = data.google_compute_network.gcp_vpc.id
  dest_range = data.aws_vpc.aws_vpc.cidr_block
  priority   = 100

  next_hop_vpn_tunnel = google_compute_vpn_tunnel.gcp_vpn_cnx.id
}
