#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 51;
use Test::Mojo;
use Mojolicious::Lite;
use Mojo::JSON;

my $t = Test::Mojo->new;

my $app = $t->app;

$app->plugin('XML' => {
  new_xrd => ['XRD']
});
$app->plugin('XRD');

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

is(ref($subnode_1), 'Mojolicious::Plugin::XML::XRD',
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
#is($xrd->get_property('bar')->text, 'foo', 'DOM access Property');

is_deeply(
    Mojo::JSON->new->decode($xrd->to_json),
    { links => [ { rel => 'foo' }],
      properties => { bar  => 'foo' } },
    'Correct JRD');

# From https://tools.ietf.org/html/draft-hammer-hostmeta-17#appendix-A
my $jrd_doc = <<'JRD';
{
  "subject":"http://blog.example.com/article/id/314",
  "expires":"2010-01-30T09:30:00Z",
  "aliases":[
    "http://blog.example.com/cool_new_thing",
    "http://blog.example.com/steve/article/7"],

  "properties":{
    "http://blgx.example.net/ns/version":"1.3",
    "http://blgx.example.net/ns/ext":null
  },
  "links":[
    {
      "rel":"author",
      "type":"text/html",
      "href":"http://blog.example.com/author/steve",
      "titles":{
        "default":"About the Author",
        "en-us":"Author Information"
      },
      "properties":{
        "http://example.com/role":"editor"
      }
    },
    {
      "rel":"author",
      "href":"http://example.com/author/john",
      "titles":{
        "default":"The other author"
      }
    },
    {
      "rel":"copyright",
      "template":"http://example.com/copyright?id={uri}"
    }
  ]
}
JRD



my $xrd_doc = <<'XRD';
<?xml version='1.0' encoding='UTF-8'?>
<XRD xmlns='http://docs.oasis-open.org/ns/xri/xrd-1.0'
     xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'>
  <Subject>http://blog.example.com/article/id/314</Subject>
  <Expires>2010-01-30T09:30:00Z</Expires>
  <Alias>http://blog.example.com/cool_new_thing</Alias>
  <Alias>http://blog.example.com/steve/article/7</Alias>
  <Property type='http://blgx.example.net/ns/version'>1.2</Property>
  <Property type='http://blgx.example.net/ns/version'>1.3</Property>
  <Property type='http://blgx.example.net/ns/ext' xsi:nil='true' />
  <Link rel='author' type='text/html'
        href='http://blog.example.com/author/steve'>
    <Title>About the Author</Title>
    <Title xml:lang='en-us'>Author Information</Title>
    <Property type='http://example.com/role'>editor</Property>
  </Link>
  <Link rel='author' href='http://example.com/author/john'>
    <Title>The other guy</Title>
    <Title>The other author</Title>
  </Link>
  <Link rel='copyright'
        template='http://example.com/copyright?id={uri}' />
</XRD>
XRD

$xrd = $app->new_xrd($xrd_doc);

my $json = Mojo::JSON->new;

is_deeply(
  $json->decode($xrd->to_json),
  $json->decode($jrd_doc), 'JRD'
);

$xrd = $app->new_xrd($jrd_doc);

is_deeply(
  $json->decode($xrd->to_json),
  $json->decode($jrd_doc), 'JRD'
);

#diag $xrd->to_pretty_xml;

$app->routes->route('/test')->to(
  cb => sub { shift->render_xrd($xrd) }
);

$app->routes->route('/no_test')->to(
  cb => sub {
    my $c = shift;
    return $c->render_xrd(undef, $c->param('res'))
  });

$t->get_ok('/test')
  ->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => '*')
  ->element_exists('Link[rel="author"][href="http://blog.example.com/author/steve"]')
  ->element_exists('Link[rel="author"][href="http://example.com/author/john"]')
  ->element_exists('Link[rel="copyright"][template="http://example.com/copyright?id={uri}"]');

$t->get_ok('/test?rel=author')
  ->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => '*')
  ->element_exists('Link[rel="author"][href="http://blog.example.com/author/steve"]')
  ->element_exists('Link[rel="author"][href="http://example.com/author/john"]')
  ->element_exists_not('Link[rel="copyright"][template="http://example.com/copyright?id={uri}"]');

$t->get_ok('/test?rel=author%20copyright')
  ->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => '*')
  ->element_exists('Link[rel="author"][href="http://blog.example.com/author/steve"]')
  ->element_exists('Link[rel="author"][href="http://example.com/author/john"]')
  ->element_exists('Link[rel="copyright"][template="http://example.com/copyright?id={uri}"]');

$t->get_ok('/test?rel=copyright')
  ->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => '*')
  ->element_exists_not('Link[rel="author"][href="http://blog.example.com/author/steve"]')
  ->element_exists_not('Link[rel="author"][href="http://example.com/author/john"]')
  ->element_exists('Link[rel="copyright"][template="http://example.com/copyright?id={uri}"]');

$t->get_ok('/no_test?res=versuch')
  ->status_is(404)
  ->content_type_is('application/xrd+xml')
  ->header_is('Access-Control-Allow-Origin' => '*')
  ->text_is('Subject' => 'versuch');

$t->get_ok('/no_test?res=versuch&format=json')
  ->status_is(404)
  ->content_type_is('application/json')
  ->header_is('Access-Control-Allow-Origin' => '*')
  ->json_is('/subject' => 'versuch');

$t->get_ok('/no_test?res=versuch&format=jrd')
  ->status_is(404)
  ->content_type_is('application/json')
  ->header_is('Access-Control-Allow-Origin' => '*')
  ->json_is('/subject' => 'versuch');



__END__
