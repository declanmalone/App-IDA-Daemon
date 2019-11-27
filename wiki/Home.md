# Welcome to the App-IDA-Daemon wiki!

What happens if I edit this in github?

Apparently I can pull the updates with:

    git pull github master

Kind of asymmetric with local edits, which I push with:

    git subtree push --prefix wiki wiki master

Actually, it seems that I need to do *two* pushes. The first is for
the wiki, as directly above, and the second is for the main
App-IDA-Daemon repository, which is a normal push to whatever your
github remote is called:

    git push github

The upshot seems to be that as long as I do both pushes, the main
repository will include both the code and the wiki if you clone from
it. Enjoy?!

