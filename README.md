# Introduction

Curse for AI using agents from different nodes (we are trying to copy JADE system using Erlang VM).


# Concept

There is some tasks with some skill complexity (json field "task") and some sets of employers (field "employers"). We should distribute employers by tasks optimally.

Also we have to run our tasks on a separete computers and connect thair using TCP/IP.

# Using

If you have ArchLinux you can use scripts 'start\_server.sh' and 'start\_node.sh'. Otherwise see scripts source.

+ At first we should know server's IP address. You can find out it using 'start\_server.sh' script ("Server IP address: \<MY IP\>").
+ Then you should push command 'm = Manager.start\_link' to Elixir console.
+ Then you should start your nodes using start\_node.sh \<NODE\_NUM\> \<SERVER\_IP\> and push in the opened Elixir console something like n = Exchanger.start\_link "node$NODE\_NUM.json", :"server@SERVER\_IP:".
+ After server timeout all start to works.
