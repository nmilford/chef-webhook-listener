upload-chef-cookbook-post-commit-webhook
========================================

Github post commit webhook listener service that allows you to trigger a Chef cookbook upload.

This is a small Sinatra service that:

+ Accepts a Github post commit webhook.
+ Searches the commit messages for `#chefdeploy:<cookbook>`
+ Deploys the cookbook with `knife upload`
+ Notifies success or failure via email.
+ Emits a log to `/var/tmp/chefdeploy.log`

---

### Requirements

+ Ruby.
+ Git.
+ Chef.
+ A user to run as.
  + `git` setup so it can access the repo without a password via ssh keys.
  + `knife` setup so it can upload cookbooks.

---

### Setup

Setup a user for the process to run as and ensure that the user can git clone your `chef-repo` without a passwod and `knife upload` to your Chef server.

Clone this repo.

Make sure you got bundler.
`sudo gem install bundler`

In the directory your cloend the repo into, get all the depndancies.
`sudo bundle install`

Update `configure` and `before` blocks in `chef-webhook-listener.rb` to have relevant settings.

You can run the service thus:

```
thin -R config.ru -p 31335 -e production start
```

And it is easy to daemonize it with supervisord with a config like:
```
directory               = /path/containing/chef-webhook-listener/
command                 = thin -R config.ru -p 31335 -e production start
process_name            = %(program_name)s
autorestart             = true
user                    = User_You_Setup
```

Once it is up, follow [these instructions](https://help.github.com/articles/post-receive-hooks) to setup the webhook on your repo to point to `http://yourserver.com:31335/chefdeploy`.

---

### Usage

To use this in your workflow do the following.

Clone your `chef-repo` and make a change or add a cookbook to `chef-repo/cookbooks`

Make a commit with `#chefdeploy:cookbook1[,cookbook2,cookbook3,...]` in the commit message.

```
git add -a
git commit -m"Deploying my baller cookbook #chefdeploy:mycookbook"
git push origin master
```

Wait for email confirmation of failure or success.

Done.

---

### TODO:

+ Read config from a external yaml file.
+ Turn into a gem.
+ Add linting like foodcritic.