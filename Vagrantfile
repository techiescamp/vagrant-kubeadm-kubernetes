NUM_WORKER_NODES = 2

Vagrant.configure("2") do |config|
    config.vm.provision "shell", inline: <<-SHELL
        echo "192.168.56.10  master-node" >> /etc/hosts
        echo "192.168.56.11  worker-node01" >> /etc/hosts
        echo "192.168.56.12  worker-node02" >> /etc/hosts
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    SHELL
    config.vm.box = "bento/ubuntu-21.10"
    config.vm.box_check_update = true

    config.vm.define "master" do |master|
      #master.vm.box = "bento/ubuntu-21.10"
      master.vm.hostname = "master-node"
      master.vm.network "private_network", ip: "192.168.56.10"
      master.vm.provider "virtualbox" do |vb|
          vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
          vb.memory = 4096
          vb.cpus = 2
      end
      master.vm.provision "shell", path: "scripts/common.sh"
      master.vm.provision "shell", path: "scripts/master.sh"
    end

    (1..NUM_WORKER_NODES).each do |i|
      config.vm.define "node0#{i}" do |node|
        #node.vm.box = "bento/ubuntu-21.10"
        node.vm.hostname = "worker-node0#{i}"
        node.vm.network "private_network", ip: "192.168.56.1#{i}"
        node.vm.provider "virtualbox" do |vb|
            vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
            vb.memory = 2048
            vb.cpus = 1
        end
        node.vm.provision "shell", path: "scripts/common.sh"
        node.vm.provision "shell", path: "scripts/node.sh"
      end
    end

  end