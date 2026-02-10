rbenv will help you manage ruby installations.  It's a fancy way of being able to install ruby of various versions and have your PATH updated as needed.

install rbenv via git

https://github.com/rbenv/rbenv?tab=readme-ov-file#basic-git-checkout

once you have your shell updated and reloaded according to those instructions,

```rbenv install 4.0.1```

which will install ruby 4.0.1

```rbenv global 4.0.1```

which will set ruby 4.0.1 as the version you use globally

```ruby --version```

will show that the right version of ruby is active.

a gem is a ruby library.  

bundler will help you install multiple gems at the same time via Gemfile / Gemfile.lock, which is a lot like npm's package.json




