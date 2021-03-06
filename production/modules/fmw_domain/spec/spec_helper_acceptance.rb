require 'beaker-rspec/spec_helper'
require 'beaker-rspec/helpers/serverspec'
require 'winrm'

UNSUPPORTED_PLATFORMS = [ 'Solaris', 'AIX' ]

hosts.each do |host|

  if host['platform'] =~ /windows/
    include Serverspec::Helper::Windows
    include Serverspec::Helper::WinRM

    # This hack to install .net 3.5 exists because .net 3.5 has to be installed on 2012 and 2012 R2
    # in order for puppet to install
    #
    # @see PUP-1951
    # @see PUP-3965
    if host.to_s =~ /2012/
      DOTNET_HACK = <<-EOF.gsub!(/\n+/, '').gsub!(/^\s+/, '')
      $webclient = New-Object System.Net.WebClient ;
      $webclient.DownloadFile('https://googledrive.com/host/0B4_Bou5W3VsSfjRmeTBaak1Da2ZtVE95M25teWlfa0Y1NEVEYlBHNGV3S3liQTlWNTBGR0E/sxs.zip','C:\\Windows\\Temp\\sxs.zip') ;
      Add-Type -Assembly 'System.IO.Compression.FileSystem' ;
      [System.IO.Compression.ZipFile]::ExtractToDirectory('C:\\Windows\\Temp\\sxs.zip', 'C:\\Windows\\Temp\\sxs') ;
      Install-WindowsFeature Net-Framework-Core -source C:\\Windows\\Temp\\sxs ;
      shutdown /r /t 0
      EOF

      on host, powershell(DOTNET_HACK)
      sleep(30)
      host.close
      sleep(10)
      host.connection
    end

    version = ENV['PUPPET_VERSION'] || '3.7.5'
    install_puppet(:version => version)

    # Install an agent

  end

end

RSpec.configure do |c|
  project_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))

  c.formatter = :documentation

  c.before :suite do
    puppet_module_install(:source => project_root, :module_name => 'fmw_domain', :target_module_path => '/etc/puppetlabs/code/environments/production/modules')
    puppet_module_install(:source => "#{project_root}/../fmw_wls",  :module_name => 'fmw_wls', :target_module_path => '/etc/puppetlabs/code/environments/production/modules')
    puppet_module_install(:source => "#{project_root}/../fmw_inst", :module_name => 'fmw_inst', :target_module_path => '/etc/puppetlabs/code/environments/production/modules')
    puppet_module_install(:source => "#{project_root}/../fmw_jdk",  :module_name => 'fmw_jdk', :target_module_path => '/etc/puppetlabs/code/environments/production/modules')
    hosts.each do |host|
      if host['platform'] =~ /solaris/
        puppet_module_install(:source => "#{project_root}/../stdlib",   :module_name => 'stdlib', :target_module_path => '/etc/puppetlabs/code/environments/production/modules')
        puppet_module_install(:source => "#{project_root}/../registry", :module_name => 'registry', :target_module_path => '/etc/puppetlabs/code/environments/production/modules')
        on(default, 'mkdir -p /usr/jdk')
      else
        on host, puppet('module', 'install', 'puppetlabs-stdlib', '--force', '--version', '3.2.0'), :acceptable_exit_codes => [0, 1]
        on host, puppet('module', 'install', 'puppetlabs-registry', '--force', '--version', '1.1.0'), :acceptable_exit_codes => [0, 1]
      end

      if host['platform'] =~ /windows/
        endpoint = "http://127.0.0.1:5985/wsman"
        c.winrm = WinRM::WinRMWebService.new(endpoint, :ssl, :user => 'vagrant', :pass => 'vagrant', :basic_auth_only => true)
        c.winrm.set_timeout 300

        on(default, 'mkdir C:/software')
        scp_to(default, "#{ENV['SOFTWARE_FOLDER']}/jdk-7u79-windows-x64.exe", 'C:/software')
        scp_to(default, "#{ENV['SOFTWARE_FOLDER']}/fmw_12.1.3.0.0_wls.jar", 'C:/software')
        scp_to(default, "#{ENV['SOFTWARE_FOLDER']}/wls1036_generic.jar", 'C:/software')
      else
        on(default, 'mkdir /software')
        scp_to(default, "#{ENV['SOFTWARE_FOLDER']}/jdk-7u79-linux-x64.tar.gz", '/software')
        scp_to(default, "#{ENV['SOFTWARE_FOLDER']}/fmw_12.1.3.0.0_wls.jar", '/software')
        scp_to(default, "#{ENV['SOFTWARE_FOLDER']}/wls1036_generic.jar", '/software')
        # scp_to(default, "#{ENV['SOFTWARE_FOLDER']}/jdk-7u75-solaris-i586.tar.gz", '/software' )
        # scp_to(default, "#{ENV['SOFTWARE_FOLDER']}/jdk-7u75-solaris-x64.tar.gz", '/software' )
      end
    end
  end
end
