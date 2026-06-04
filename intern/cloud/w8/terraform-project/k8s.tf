#keo kubeconfig tu EC2 ve laptop (sau khi cum san sang)
resource "null_resource" "kubeconfig" {
  # cho EIP gan xong -> dung IP co dinh
  depends_on = [aws_eip_association.web]

  # re-keo neu EC2 doi
  triggers = {
    instance_id = aws_instance.web.id
  }

  connection {
    type        = "ssh"
    host        = aws_eip.web.public_ip
    user        = "ec2-user"
    private_key = tls_private_key.ssh.private_key_pem
  }

  # cho toi khi user_data tao xong kubeconfig.ext
  provisioner "remote-exec" {
    inline = [
      "echo cho minikube + kubeconfig.ext ...",
      "until [ -f /home/ec2-user/kubeconfig.ext ]; do sleep 5; done",
      "echo cum san sang",
    ]
  }

  # keo file ve thu muc module (kubernetes provider doc tu day)
  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${local_file.ssh_key.filename} ec2-user@${aws_eip.web.public_ip}:/home/ec2-user/kubeconfig.ext ${path.module}/kubeconfig"
  }
}

# app static HTML (ConfigMap + Deployment + Service)

# ConfigMap chua trang HTML tinh
resource "kubernetes_config_map" "html" {
  depends_on = [null_resource.kubeconfig]
  metadata {
    name = "web-html"
  }
  data = {
    "index.html" = <<-HTML
      <!doctype html>
      <html>
        <head><meta charset="utf-8"><title>K8s on AWS - Terraform 1-Click</title></head>
        <body style="font-family:sans-serif;text-align:center;margin-top:4%;background:#0f172a;color:#e2e8f0">
          <h1>Hello from Kubernetes on AWS</h1>
          <p>If you see this video it means it's a success — enjoy</p>
          <video src="yes_web.mp4" autoplay muted loop playsinline controls
                 style="max-height:70vh;border-radius:14px;box-shadow:0 8px 30px rgba(0,0,0,.5)"></video>
        </body>
      </html>
    HTML
  }

  # video nhung qua binaryData (643KB < cap 1MB ConfigMap)
  binary_data = {
    "yes_web.mp4" = filebase64("${path.module}/yes_web.mp4")
  }
}

# Deployment nginx, mount HTML tu ConfigMap
resource "kubernetes_deployment" "web" {
  depends_on = [null_resource.kubeconfig]
  metadata {
    name   = "web"
    labels = { app = "web" }
  }
  spec {
    replicas = 2
    selector {
      match_labels = { app = "web" }
    }
    template {
      metadata {
        labels = { app = "web" }
      }
      spec {
        container {
          name  = "web"
          image = "nginx:1.27"
          port {
            container_port = 80
          }
          volume_mount {
            name       = "html"
            mount_path = "/usr/share/nginx/html"
          }
        }
        volume {
          name = "html"
          config_map {
            name = kubernetes_config_map.html.metadata[0].name
          }
        }
      }
    }
  }
}

# Service NodePort 30080 (khop socat-app + target group)
resource "kubernetes_service" "web" {
  depends_on = [null_resource.kubeconfig]
  metadata {
    name = "web"
  }
  spec {
    selector = { app = "web" }
    type     = "NodePort"
    port {
      port        = 80
      target_port = 80
      node_port   = 30080
    }
  }
}
