#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 8;

use_ok('Mojolicious::Plugin::XML::HostMeta');
use_ok('Mojolicious::Plugin::XML::XRD');

$SIG{'__WARN__'} = sub {};
ok( !Mojolicious::Plugin::XML::HostMeta->new, 'Only extension');
$SIG{'__WARN__'} = undef;

my $xrd = Mojolicious::Plugin::XML::XRD->new;

ok($xrd, 'XRD');

ok($xrd->add_extension('Mojolicious::Plugin::XML::HostMeta'), 'HostMeta');

ok($xrd->add_host('sojolicio.us'), 'Add host');

is($xrd->at('Host')->namespace, 'http://host-meta.net/xrd/1.0', 'Namespace');
is($xrd->at('Host')->text, 'sojolicio.us', 'Host');

