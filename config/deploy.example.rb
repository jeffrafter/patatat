set :application, "patatat"
set :domain, CLI.ui.ask("Domain you are deploying to (IP Address or Hostname): ")
set :deploy_to, "/var/www/#{application}"
set :repository,  "git://github.com/jeffrafter/patatat.git"
set :scm, :git
set :keep_releases, 2
set :user, "deploy"
set :runner, "patatat"
set :use_sudo, :false

role :app, "#{domain}"
role :web, "#{domain}"
role :db,  "#{domain}", :primary => true

# == CONFIG ====================================================================
namespace :init do
  namespace :config do
    desc "Create shared configuration"
    task :patatat do
      if Capistrano::CLI.ui.ask("Create patatat configuration? (y/n): ") == 'y'
        set :twitter_user, Capistrano::CLI.ui.ask("twitter user: ")
        set :twitter_pass, Capistrano::CLI.password_prompt("twitter password: ")      
        patatat_configuration =<<-EOF
---
twitter:
  username: #{twitter_user}
  password: #{twitter_pass}
EOF
        sudo "mkdir -p #{shared_path}"
        sudo "chown deploy:deploy #{shared_path}"
        run <<-COMMAND
          mkdir -p #{shared_path}/config &&
          mkdir -p #{shared_path}/yoke &&
          mkdir -p #{shared_path}/database &&
          mkdir -p #{shared_path}/tmp &&
          mkdir -p #{shared_path}/tmp/pids &&
          mkdir -p #{shared_path}/log &&
          touch #{shared_path}/log/yell.log
        COMMAND
        put patatat_configuration, "#{shared_path}/config/patatat.conf"
      end    
    end
    
    desc "Symlink shared configurations to current"
    task :localize, :roles => [:app] do
      run <<-COMMAND
        ln -nsf #{shared_path}/config/patatat.conf #{release_path}/config/patatat.conf &&
        ln -nsf #{shared_path}/yoke #{release_path}/yoke &&
        ln -nsf #{shared_path}/database #{release_path}/database &&
        ln -nsf #{shared_path}/log #{release_path}/log && 
        ln -nsf #{shared_path}/tmp/pids #{release_path}/tmp/pids 
      COMMAND

      sudo "chown -R patatat:patatat #{release_path}/config/"
      sudo "chown -R patatat:patatat #{release_path}/yoke/"
      sudo "chown -R patatat:patatat #{release_path}/database/"
      sudo "chown -R patatat:patatat #{release_path}/log/"
      sudo "chown -R patatat:patatat #{release_path}/tmp/pids/"
    end 		    
  end
end

# == DEPLOY ======================================================================
namespace :deploy do
  desc "Start patatat"
  task :start do
    sudo  "su - patatat -c \"cd /var/www/patatat/current && script/patatat\" &"
  end
  
  desc "Stop patatat"
  task :stop do
    puts "Not currently implemented"
  end
  
  desc "Restart patatat"
  task :restart do
    puts "Not currently implemented"
  end  

  desc "Finalize the update"
  task :finalize_update, :except => { :no_release => true } do
    run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)
    run <<-COMMAND
      rm -rf #{latest_release}/log #{latest_release}/tmp/pids &&
      mkdir -p #{latest_release}/tmp &&
      ln -s #{shared_path}/log #{latest_release}/log &&
      ln -s #{shared_path}/tmp/pids #{latest_release}/tmp/pids
    COMMAND
  end  

end

# == TASKS =====================================================================
after "deploy", "deploy:cleanup"
after "deploy:setup", "init:config:patatat"
after "deploy:symlink", "init:config:localize"

task :after_update_code do
end