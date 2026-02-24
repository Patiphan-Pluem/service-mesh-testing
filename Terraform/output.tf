output "private_key_pem" {
    description = "Save this content to 'k3s_server.pem' to SSH"
    value = tls_private_key.k3s_server_pk.private_key_pem
    sensitive = true
}

output "public_ip" {
  description = "Public IP ของ K3s Node"
  value       = aws_instance.k3s_server.public_ip
}