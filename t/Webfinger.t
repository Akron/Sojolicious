#!/usr/bin/perl
use strict;
use warnings;

$|++;
use lib '../lib';

use Test::More tests => 8;
use Test::Mojo;
use Mojolicious::Lite;

my $t = Test::Mojo->new;
my $app = $t->app;
my $acct = 'acct:akron@sojolicio.us';
$app->plugin('webfinger' =>
	     { host => 'sojolicio.us', secure => 1 });

$app->routes->route('/webfinger')->webfinger('q');

is($app->hostmeta->get_link('lrdd')->attrs->{template},
   'https://sojolicio.us/webfinger?q={uri}',
   'Correct uri');

is ($app->endpoint('webfinger' => {uri => $acct}),
    'https://sojolicio.us/webfinger?q='.$acct,
    'Webfinger endpoint');

$app->hook('before_serving_webfinger' => sub {
    my ($c, $norm, $xrd) = @_;
    if ($norm eq $acct) {

	$xrd->add_link( 'http://microformats.org/profile/hcard',
			{   type => 'text/html',
			    href => 'http://sojolicio.us/akron.hcard' });

	$xrd->add_link('describedby',
		       {   type => 'application/rdf+xml',
			   href => 'http://sojolicio.us/akron.foaf' });
    } else {
	$xrd = undef;
    };
	   });

my $wf = $app->webfinger($acct);

ok($wf, 'Webfinger');
is($wf->at('Subject')->text, $acct, 'Subject');
is($wf->get_link('http://microformats.org/profile/hcard')
   ->attrs('href'), 'http://sojolicio.us/akron.hcard',
                    'Webfinger-hcard');
is($wf->get_link('http://microformats.org/profile/hcard')
   ->attrs('type'), 'text/html',
                    'Webfinger-hcard-type');
is($wf->get_link('describedby')
   ->attrs('href'), 'http://sojolicio.us/akron.foaf',
                    'Webfinger-described_by');
is($wf->get_link('describedby')
   ->attrs('type'), 'application/rdf+xml',
                    'Webfinger-descrybed_by-type');

__END__
