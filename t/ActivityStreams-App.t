#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::Mojo;
use Mojolicious::Lite;

use Test::More tests => 1;

my $t = Test::Mojo->new;
my $app = $t->app;

$app->plugin('activity_streams');

# Plugin helper
my $as = $app->new_activity;


my $as_string = $as->to_pretty_xml;
$as_string =~ s/[\s\r\n]+//g;

is ($as_string, '<?xmlversion="1.0"encoding="UTF-8'.
                '"standalone="yes"?><feedxmlns="ht'.
                'tp://www.w3.org/2005/Atom"xmlns:a'.
                'ctivity="http://activitystrea.ms/'.
                'schema/1.0/"/>',
                'Initial ActivityStream');

