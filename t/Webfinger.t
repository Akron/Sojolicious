#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 1;
use Test::Mojo;
use Mojolicious::Lite;

my $t = Test::Mojo->new;

my $app = $t->app;

$app->plugin('webfinger' =>
	     { host => 'sojolicio.us', secure => 1 });

$app->routes->route('/webfinger')->webfinger('q');

is($app->hostmeta->get_link('lrdd')->attrs->{template},
   'https://sojolicio.us/webfinger?q={uri}',
   'Correct uri');

__END__
