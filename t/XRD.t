#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 11;
use Test::Mojo;
use Mojolicious::Lite;
use Mojo::JSON;

my $t = Test::Mojo->new;

my $app = $t->app;

$app->plugin('x_r_d');

# Silence
$app->log->level('error');

my $xrd = $app->new_xrd;

my $xrd_string = $xrd->to_pretty_xml;

$xrd_string =~ s/[\s\r\n]+//g;

is ($xrd_string, '<?xmlversion="1.0"encoding="UTF-8"'.
                 'standalone="yes"?><XRDxmlns="http:'.
                 '//docs.oasis-open.org/ns/xri/xrd-1'.
                 '.0"xmlns:xsi="http://www.w3.org/20'.
                 '01/XMLSchema-instance"/>',
                 'Initial XRD');

my $subnode_1 = $xrd->add('Link',{ rel => 'foo' }, 'bar');

is(ref($subnode_1), 'Mojolicious::Plugin::XRD::Document',
   'Subnode added');

is($xrd->at('Link')->attrs('rel'), 'foo', 'Attribute');
is($xrd->at('Link[rel="foo"]')->text, 'bar', 'Text');

my $subnode_2 = $subnode_1->comment("Foobar Link!");

is($subnode_1, $subnode_2, "Comment added");

$xrd = $app->new_xrd(<<'XRD');
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<XRD xmlns="http://docs.oasis-open.org/ns/xri/xrd-1.0"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <!-- Foobar Link! -->
  <Link rel="foo">bar</Link>
</XRD>
XRD

ok($xrd, 'XRD loaded');

is($xrd->at('Link[rel="foo"]')->text, 'bar', "DOM access Link");
is($xrd->get_link('foo')->text, 'bar', "DOM access Link");

$xrd->add('Property', { type => 'bar' }, 'foo');

is($xrd->at('Property[type="bar"]')->text, 'foo', 'DOM access Property');
is($xrd->get_property('bar')->text, 'foo', 'DOM access Property');

is_deeply(
    Mojo::JSON->new->decode($xrd->to_json),
    { links => [ { rel => 'foo' }],
      properties => { bar  => 'foo' } },
    'Correct JRD');

__END__
