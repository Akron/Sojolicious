use Test::More tests => 16;
use Math::BigInt;
use strict;
use warnings;
no strict 'refs';

use lib '../lib';

our $module;
BEGIN {
    our $module = 'Mojolicious::Plugin::MagicKey';
    use_ok($module, qw(b64url_encode
                       b64url_decode));            # 1
};

my $test_msg = 'This is a small message test.';

# test os2ip
my $os2ip = *{"${module}::_os2ip"}->($test_msg);
ok($os2ip eq '22756313778701413365784'.
             '01782410999343477943894'.
             '174703601131715860591662', 'os2ip'); # 2

# test i2osp
my $i2osp = *{"${module}::_i2osp"}->($os2ip);
ok($i2osp eq $test_msg, 'i2osp');                  # 3

# test bitsize
my $bitsize = *{"${module}::_bitsize"}->($os2ip);
ok($bitsize == 231, 'bitsize');                    # 4

# test octet_len
my $octet_len = *{"${module}::_octet_len"}->($os2ip);
ok($octet_len == 29, 'octet_len');                 # 5

my $b64url_encode = b64url_encode($test_msg);
$b64url_encode =~ s/[\s=]+$//;
ok($b64url_encode eq 'VGhpcyBpcyBhIHNtYWxsIG1lc3NhZ2UgdGVzdC4',
   'b64url_encode');                               # 6

my $b64url_decode = b64url_decode($b64url_encode);
ok($b64url_decode eq $test_msg, 'b64url_decode');  # 7

my $test_key = 'RSA.'.
    'mVgY8RN6URBTstndvmUUPb4UZTdwvw'.
    'mddSKE5z_jvKUEK6yk1u3rrC9yN8k6'.
    'FilGj9K0eeUPe2hf4Pj-5CmHww==.'.
    'AQAB.'.
    'Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6'.
    'yihYetQ8jy-jZXdsZXd8V5ub3kuBHH'.
    'k4M39i3TduIkcrjcsiWQb77D8Q==';

my $mkey = Mojolicious::Plugin::MagicKey->new($test_key); 

ok($mkey, 'Magic-Key parsed');                     # 8
ok($mkey->n eq '80312837890751965650228915'.
               '46563591368344944062154100'.
               '50964539889229343337085989'.
               '19433064399074548837475344'.
               '93461257620351548796452092'.
               '307094036643522661681091',
                        'M-Key modulus correct');  # 9
ok($mkey->d eq '24118237980497878083558223'.
               '37426462024816467706597110'.
               '82488260212703094530069868'.
               '86574485408953662105923805'.
               '76050280953899102635751538'.
               '748696981555132000814065',
                        'M-Key private exponent'); # 10
ok($mkey->e == 65537,   'M-Key exponent');         # 11
ok($mkey->emLen == 64,  'M-Key length correct');   # 12

$test_msg =    'test string';

# From https://github.com/sivy/Salmon/blob/master/t/30-magic-algorithms.t
my $test_sig = 'mNpBIpTUOESnuQMlS8aWZ4hwdS'.
               'wWnMstrn0F3L9GHDXa238fN3Bx'.
               '3Rl0yvVESM_eZuocLsp9ubUrYD'.
               'u83821fQ==';

my $emsa = *{"${module}::_emsa_encode"}->($test_msg,
					  $mkey->emLen,
					  'sha-256');

my $test_emsa = 'Af____________8AMDEwDQYJY'.
                'IZIAWUDBAIBBQAEINVXnEbfzH'.
                '8YIHAT5ltE5MtOLCKY9KxFe6j'.
                '4J0PzHpML';

ok(b64url_encode($test_msg) eq 'dGVzdCBzdHJpbmc=',
    'b64url correct');                             # 13

ok(b64url_encode($emsa) eq $test_emsa,
                     'Emsa correct');              # 14

my $sig = $mkey->sign($test_msg);
ok($sig eq $test_sig,  'Signature correct');       # 15

SKIP: {
    skip 'Not working', 1;
    $mkey->d( undef ); # Delete private part

    ok($mkey->verify($test_msg, $test_sig), 'Signature okay.');
};
