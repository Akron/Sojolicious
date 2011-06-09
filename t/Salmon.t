use Test::More tests => 1;
use Test::Mojo;
use strict;
use warnings;

$|++;

use lib '../lib';

use Mojolicious::Lite;

my $t = Test::Mojo->new;

my $app = $t->app;

$app->plugin('host_meta' => { host => 'sojolicio.us' });
$app->plugin('salmon');

my $r = $app->routes;

my $salmon = $r->route('/salmon');
$salmon->route('/mentioned')->salmon('mentioned');
$salmon->route('/all-replies')->salmon('all-replies');
$salmon->route('/signer')->salmon('signer');

my $mkey = <<'RSAKEY';
  RSA.
  mVgY8RN6URBTstndvmUUPb4UZTdwvw
  mddSKE5z_jvKUEK6yk1u3rrC9yN8k6
  FilGj9K0eeUPe2hf4Pj-5CmHww==.
  AQAB.
  Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6
  yihYetQ8jy-jZXdsZXd8V5ub3kuBHH
  k4M39i3TduIkcrjcsiWQb77D8Q==
RSAKEY

my $me = $app->magicenvelope(
    { data => 'test string',
      data_type => 'text/plain'}
    );
$me->sign( { 'key' => $mkey });

warn $t->post_ok('/all-replies', {}, $me->to_xml)
    ->status_is(200)
    ->content_is('p' => 'Thank you for your reply.');

# Do: GET-Frage im Default ist falsch.
