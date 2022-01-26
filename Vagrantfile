Vagrant.configure("2") do |config|
    config.vm.provision "shell", inline: <<-SHELL
        apt-get update -y
        echo "192.0.0.10  master-node" >> /etc/hosts
        echo "192.0.0.11  worker-node01" >> /etc/hosts
        echo "192.0.0.12  worker-node02" >> /etc/hosts
    SHELL
    
    config.vm.define "master" do |master|
      master.vm.box = "mpasternak/focal64-arm"
      master.vm.hostname = "master-node"
      master.vm.network "private_network", ip: "192.0.0.10"
      master.vm.provider "virtualbox" do |vb|
          vb.memory = 1500
          vb.cpus = 1
      end
      master.vm.provision "shell", path: "scripts/common.sh"
      master.vm.provision "shell", path: "scripts/master.sh"
    end

    (1..2).each do |i|
  
    config.vm.define "node0#{i}" do |node|
      node.vm.box = "mpasternak/focal64-arm"
      node.vm.hostname = "worker-node0#{i}"
      node.vm.network "private_network", ip: "192.0.0.1#{i}"
      node.vm.provider "virtualbox" do |vb|
          vb.memory = 1500
          vb.cpus = 1
      end
      node.vm.provision "shell", path: "scripts/common.sh"
      node.vm.provision "shell", path: "scripts/node.sh"
    end
    
    end
  end
