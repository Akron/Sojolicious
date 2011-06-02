#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 8;
use Test::Mojo;

use_ok('Mojolicious::Plugin::XRD');

my $xrd = Mojolicious::Plugin::XRD->new;

ok($xrd, 'XRD established');

my $xrd_string = $xrd->to_xml;

$xrd_string =~ s/[\s\r\n]+//g;

is ($xrd_string, '<?xmlversion="1.0"encoding="UTF-8"'.
                 'standalone="yes"?><XRDxmlns="http:'.
                 '//docs.oasis-open.org/ns/xri/xrd-1'.
                 '.0"xmlns:xsi="http://www.w3.org/20'.
                 '01/XMLSchema-instance"/>',
                 'Initial XRD');

my $subnode_1 = $xrd->add('Link',{ rel => 'foo' }, 'bar');

is(ref($subnode_1), 'Mojolicious::Plugin::XRD::Node',
   'Subnode added');

my $subnode_2 = $subnode_1->comment("Foobar Link!");

is($subnode_1, $subnode_2, "Comment added");

$xrd = Mojolicious::Plugin::XRD->new(<<'XRD');
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<XRD xmlns="http://docs.oasis-open.org/ns/xri/xrd-1.0"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <!-- Foobar Link! -->
  <Link rel="foo">bar</Link>
</XRD>
XRD

ok($xrd, 'XRD loaded');

is($xrd->get_link('foo')->text, 'bar', "DOM access Link");

$xrd->add('Property', { type => 'bar' }, 'foo');

is($xrd->get_property('bar')->text, 'foo', 'DOM access Property');

__END__
