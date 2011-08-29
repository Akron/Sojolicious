#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::Mojo;
use Mojolicious::Lite;

use Test::More tests => 19;

my $t = Test::Mojo->new;
my $app = $t->app;
my $c = Mojolicious::Controller->new;
$c->app($app);

$app->plugin('magic_signatures');

my $h = $app->renderer->helpers;

# XRD
ok($h->{new_xrd}, 'render_xrd fine.');
ok($h->{render_xrd}, 'render_xrd fine.');

# Hostmeta
ok($h->{hostmeta}, 'hostmeta fine.');
ok($h->{endpoint}, 'endpoint fine.');

# Webfinger
ok($h->{webfinger}, 'webfinger fine.');
ok($h->{parse_acct}, 'parse_acct fine.');

# Magic Signatures
ok($h->{magicenvelope}, 'magicenvelope fine.');
ok($h->{magickey}, 'magickey fine.');
ok($h->{get_magickeys}, 'get_mks fine.');
ok($h->{verify_magicenvelope}, 'verify_me fine.');

# Reverse check
ok(!exists $h->{foobar}, 'foobar not fine.');

$t->get_ok('/.well-known/host-meta')
    ->status_is(200)
    ->content_type_is('application/xrd+xml')
    ->element_exists('XRD')
    ->element_exists('XRD[xmlns]')
    ->element_exists('XRD[xsi]')
    ->element_exists_not('Link')
    ->element_exists_not('Property');

