use Test::More tests => 1;
use Test::Mojo;
use strict;
use warnings;
$|++;

use lib '../lib';

use_ok('Mojolicious::Plugin::MagicSignatures::Envelope');

my $me = Mojolicious::Plugin::MagicSignatures::Envelope->new(
    {	
	data => 'Some arbitrary string.',
	data_type => 'text/plain'
    });

my $mkey =  Mojolicious::Plugin::MagicSignatures::Key->new(<<'MKEY');
  RSA.
  mVgY8RN6URBTstndvmUUPb4UZTdwvw
  mddSKE5z_jvKUEK6yk1u3rrC9yN8k6
  FilGj9K0eeUPe2hf4Pj-5CmHww==.
  AQAB.
  Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6
  yihYetQ8jy-jZXdsZXd8V5ub3kuBHH
  k4M39i3TduIkcrjcsiWQb77D8Q==
MKEY

$me->sign(undef => $mkey);
#diag $me->signed;
#diag $mkey->to_string;
#diag $me->to_compact;
#diag $me->to_xml;
#diag $me->to_json;
