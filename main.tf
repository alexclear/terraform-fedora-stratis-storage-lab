variable "insecure_no_strict_host_key_checking" {
  default = true
}

provider "libvirt" {
  uri = "qemu:///system"
}

# We fetch the latest ubuntu release image from their mirrors
resource "libvirt_volume" "fedora_stratisd" {
  name   = "fedora-stratisd-orig.img"
  pool   = "default"
  source = "https://mirror.yandex.ru/fedora/linux/releases/29/Cloud/x86_64/images/Fedora-Cloud-Base-29-1.2.x86_64.qcow2"
  format = "qcow2"
}

resource "libvirt_volume" "fedora_stratisd_root" {
  name   = "fedora-stratisd-root.img"
  base_volume_id = "${libvirt_volume.fedora_stratisd.id}"
  size = 23613931520
  pool   = "default"
  format = "qcow2"
}

resource "libvirt_volume" "fedora_stratisd_data" {
  name   = "fedora-stratisd-data.img"
  size = 23613931520
  pool   = "default"
  format = "qcow2"
}

data "template_file" "user_data" {
  template = "${file("${path.module}/cloud_init.cfg")}"
}

data "template_file" "meta_data" {
  template = "${file("${path.module}/meta_data.cfg")}"
}

# for more info about paramater check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field
resource "libvirt_cloudinit_disk" "commoninit" {
  name           = "commoninit-fedora-stratisd.iso"
  user_data      = "${data.template_file.user_data.rendered}"
  meta_data      = "${data.template_file.meta_data.rendered}"
}

resource "libvirt_domain" "fedora_stratisd" {
  name = "fedora-stratisd"
  memory = 4096
  vcpu = 2
  qemu_agent = true

  cloudinit = "${libvirt_cloudinit_disk.commoninit.id}"

  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  # IMPORTANT: this is a known bug on cloud images, since they expect a console
  # we need to pass it
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = "${libvirt_volume.fedora_stratisd_root.id}"
  }

  disk {
    volume_id = "${libvirt_volume.fedora_stratisd_data.id}"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  connection {
    user = "tfuser"
    host = element(element(self.*.network_interface.0.addresses, 0), 0)
  }

  provisioner "ansible" {
    plays {
      playbook {
        file_path = "${path.module}/ansible/playbooks/create-stratis-volume.yml"
        roles_path = [
            "${path.module}/ansible/roles"
        ]
      }
      hosts = ["fedora-stratisd"]
      extra_vars = {
        ansible_python_interpreter = "python3"
      }
    }
    ansible_ssh_settings {
      insecure_no_strict_host_key_checking = "${var.insecure_no_strict_host_key_checking}"
    }
  }
}

output "ipv4" {
  value = element(element(libvirt_domain.fedora_stratisd.*.network_interface.0.addresses, 0), 0)
}
