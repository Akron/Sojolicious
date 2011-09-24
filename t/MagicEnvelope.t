#!/usr/bin/env perl
use Test::More tests => 7;
use Test::Mojo;
use strict;
use warnings;
$|++;

use lib '../lib';

use_ok('Mojolicious::Plugin::MagicSignatures::Envelope');

my $test_msg = 'Not really Atom'; # Tm90IHJlYWxseSBBdG9t
my $test_data_type = 'application/atom+xml';

my $mkey_string =  '
  RSA.
  mVgY8RN6URBTstndvmUUPb4UZTdwvw
  mddSKE5z_jvKUEK6yk1u3rrC9yN8k6
  FilGj9K0eeUPe2hf4Pj-5CmHww==.
  AQAB.
  Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6
  yihYetQ8jy-jZXdsZXd8V5ub3kuBHH
  k4M39i3TduIkcrjcsiWQb77D8Q==';

my $me = Mojolicious::Plugin::MagicSignatures::Envelope->new(
    {
	data => 'Some arbitrary string.',
	data_type => 'text/plain'
    });

is($me->sig_base,
   'U29tZSBhcmJpdHJhcnkgc3RyaW5nLg.'.
   'dGV4dC9wbGFpbg==.'.
   'YmFzZTY0dXJs.'.
   'UlNBLVNIQTI1Ng==', 'Base String');

ok(!$me->signed, 'Envelope not signed');

$me->sign(undef, $mkey_string);

ok($me->signed, 'Envelope signed');

my $mkey = Mojolicious::Plugin::MagicSignatures::Key->new(<<'MKEY');
  RSA.
  mVgY8RN6URBTstndvmUUPb4UZTdwvw
  mddSKE5z_jvKUEK6yk1u3rrC9yN8k6
  FilGj9K0eeUPe2hf4Pj-5CmHww==.
  AQAB
MKEY

ok($me->verify([[$mkey]]), 'MagicEnvelope Verification');

my $xml = $me->to_xml;
$xml =~ s/\s//gm;

is ($xml, '<?xmlversion="1.0"encoding="U'.
      'TF-8"standalone="yes"?><me:envxml'.
      'ns:me="http://salmon-protocol.org'.
      '/ns/magic-env"><me:datatype="text'.
      '/plain">U29tZSBhcmJpdHJhcnkgc3Rya'.
      'W5nLg</me:data><me:encoding>base6'.
      '4url</me:encoding><me:alg>RSA-SHA'.
      '256</me:alg><me:sig>UFF5N0tlVEJWU'.
      'mY3dWZQUlhUeFZsaExSU0dkLUZ4cS14Vm'.
      '9TbUJBYU1tNVVOUDJmNnZUa0dDYklfTUh'.
      'yNm0xRUJfdllNYmxrbUtCMm40R09YVFdQ'.
      'M3c9PQ==</me:sig></me:env>',
  'XML Generation');

my $compact = $me->to_compact;

is ($me->to_compact,
  '.UFF5N0tlVEJWUmY3dWZQUlhUeFZsaExSU0dk'.
  'LUZ4cS14Vm9TbUJBYU1tNVVOUDJmNnZUa0dDY'.
  'klfTUhyNm0xRUJfdllNYmxrbUtCMm40R09YVF'.
  'dQM3c9PQ==.U29tZSBhcmJpdHJhcnkgc3RyaW'.
  '5nLg.dGV4dC9wbGFpbg==.YmFzZTY0dXJs.Ul'.
  'NBLVNIQTI1Ng==',
  'Compact serialization')

__END__
