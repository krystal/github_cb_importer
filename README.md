# GitHub to Codebase Importer

This script will import your issues from GitHub to Codebase

## Requirements

This importer relies on the new GitHub API v3, documented here: 
http://developer.github.com/v3/.

Tested on Ruby 1.9.3p194. Requires the JSON gem. To install run:

    gem install json

## Usage

You should have all users involved in your discussions created in Codebase 
prior to running this script. The importer will attempt to make a match between
users based upon their primary email addresses. If no match is found for that
user, the name will still be copied correctly, but there will be no link to
that user, and entries will show up as "Unknown Entity" in your Codebase
activity feed.

Edit the script and enter your GitHub and Codebase credentials in the 
appropriate constants.

Execute github_cb_installer.rb:

    ruby github_cb_installer.rb

## Improvements

Please feel free to improve this script to include new functionality or 
bugfixes. Just submit a pull request when you're done.