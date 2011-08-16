use Test::More tests => 2;
use Test::Mojo;
use strict;
use warnings;
$|++;

use lib '../lib';

use_ok('Mojolicious::Plugin::MagicSignatures::Envelope');

my $test_msg = 'Not really Atom'; # Tm90IHJlYWxseSBBdG9t
my $test_data_type = 'application/atom+xml';

my $sig_base = Mojolicious::Plugin::MagicSignatures::Envelope::_sig_base(
    $test_msg,
    $test_data_type);

is($sig_base,
   'Tm90IHJlYWxseSBBdG9t.YXBwbGljYXRpb24vYXRvbSt4bWw=.'.
   'YmFzZTY0dXJs.UlNBLVNIQTI1Ng',
   'Correct signature base string');

__END__

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
