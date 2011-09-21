#!/usr/bin/env perl

use Test::More tests => 27;
use Math::BigInt try => 'GMP,Pari';
use strict;
use warnings;
no strict 'refs';

use lib '../lib';

our $module;
BEGIN {
    our $module = 'Mojolicious::Plugin::MagicSignatures::Key';
    use_ok($module);                                # 1
    use_ok('Mojolicious::Plugin::Util::Base64url'); # 2
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

# test from http://cpansearch.perl.org/src/VIPUL/Crypt-RSA-1.99/t/01-i2osp.t
my $number = 4; 
$i2osp = *{"${module}::_i2osp"}->($number, 4);
$os2ip = *{"${module}::_os2ip"}->($i2osp);

is($os2ip, $number, 'Crypt::RSA::Test i2osp and os2ip - 1');

$number = '1234857092384759348579032847529875982374'.
    '5092384759238475903248759238475246534653984765'.
    '8327456823746587342658736587324658736453548634'.
    '9864390323422374897503987560374089721346786456'.
    '7836498734612897468237648745698743648796487932'.
    '6487964378569287346529'; 
$i2osp = *{"${module}::_i2osp"}->($number, 102);
$os2ip = *{"${module}::_os2ip"}->($i2osp);

is($os2ip, $number, 'Crypt::RSA::Test i2osp and os2ip - 2');

my $string = 'abcdefghijklmnopqrstuvwxyz-'.
    '0123456789-abcdefghijklmnopqrstuvwxy'.
    'z-abcdefghijklmnopqrstuvwxyz-0123456'.
    '789';
$number = Math::BigInt->new('166236188672784693770242514753'.
			    '420034912412776787232632921068'.
			    '824014646347893937590064771712'.
			    '921923774969379936913356439094'.
			    '695954550320707099033382274920'.
			    '372913421785829711983357001510'.
			    '792400267452442816935867829132'.
			    '703234881800415259286201953001'.
			    '355321');

$os2ip = *{"${module}::_os2ip"}->($string);

is($os2ip, $number, 'Crypt::RSA::Test i2osp and os2ip - 3');

$i2osp = *{"${module}::_i2osp"}->($os2ip);

is($i2osp, $string, 'Crypt::RSA::Test i2osp and os2ip - 4');

$i2osp = *{"${module}::_i2osp"}->($number);

is($i2osp, $string, 'Crypt::RSA::Test i2osp and os2ip - 5');

$string = "abcd";
$number = 1_633_837_924;

$os2ip = *{"${module}::_os2ip"}->($string);

is($os2ip, $number, 'Crypt::RSA::Test i2osp and os2ip - 6');

$i2osp = *{"${module}::_i2osp"}->($os2ip);

is($i2osp, $string, 'Crypt::RSA::Test i2osp and os2ip - 7');

$i2osp = *{"${module}::_i2osp"}->($number);

is($i2osp, $string, 'Crypt::RSA::Test i2osp and os2ip - 8');





$os2ip = *{"${module}::_os2ip"}->($test_msg);

# test bitsize
my $bitsize = *{"${module}::_bitsize"}->($os2ip);
is(231, $bitsize, 'bitsize');                    # 4

# test octet_len
my $octet_len = *{"${module}::_octet_len"}->($os2ip);
is(29, $octet_len, 'octet_len');                 # 5

my $b64url_encode = b64url_encode($test_msg);
$b64url_encode =~ s/[\s=]+$//;
is($b64url_encode, 'VGhpcyBpcyBhIHNtYWxsIG1lc3NhZ2UgdGVzdC4',
   'b64url_encode');                               # 6

my $b64url_decode = b64url_decode($b64url_encode);
ok($b64url_decode eq $test_msg, 'b64url_decode');  # 7

# Check for broken Math::BigInt by
# https://salmon-protocol.googlecode.com/svn/trunk/
#   lib/python/magicsig_hjfreyer/magicsigalg_test.py
my $n = Math::BigInt->new(2)->bpow(2048)->badd(42);
my $test_n = Math::BigInt->new(<<'BIGN');
32317006071311007300714876688669951960444102669715484032130345427524655138867890893197201411522913463688717960921898019494119559150490921095088152386448283120630877367300996091750197750389652106796057638384067568276792218642619756161838094338476170470581645852036305042887575891541065808607552399123930385521914333389668342420684974786564569494856176035326322058077805659331026192708460314150258592864177116725943603718461857357598351152301645904403697613233287231227125684710820209725157101726931323469678542580656697935045997268352998638215525166389437335543602135433229604645318478604952148193555853611059596230698
BIGN

ok($n->is_even($test_n), 'Math::BigInt');

my $b64_n = b64url_encode($n);
is(b64url_decode($b64_n), $n, 'b64url for big numbers');

# https://salmon-protocol.googlecode.com/
#   svn/trunk/lib/python/magicsig_hjfreyer/magicsig_example.py
my $test_key = 
    'RSA.'.
    'mVgY8RN6URBTstndvmUUPb4UZTdwvw'.
    'mddSKE5z_jvKUEK6yk1u3rrC9yN8k6'.
    'FilGj9K0eeUPe2hf4Pj-5CmHww==.'.
    'AQAB.'.
    'Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6'.
    'yihYetQ8jy-jZXdsZXd8V5ub3kuBHH'.
    'k4M39i3TduIkcrjcsiWQb77D8Q==';

my $mkey = Mojolicious::Plugin::MagicSignatures::Key->new($test_key); 

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

my $test_public_key = $test_key;
$test_public_key =~ s{\.[^\.]+$}{};

is($mkey->to_string, $test_public_key, 'M-Key string correct');

my $emsa = *{"${module}::_emsa_encode"}->($test_msg,
					  $mkey->emLen,
					  'sha-256');

my $test_emsa = 'Af____________8AMDEwDQYJY'.
                'IZIAWUDBAIBBQAEINVXnEbfzH'.
                '8YIHAT5ltE5MtOLCKY9KxFe6j'.
                '4J0PzHpML';

# https://salmon-protocol.googlecode.com/svn/
#   trunk/lib/python/magicsig_hjfreyer/magicsig_test.py
$test_msg = q{<?xml version='1.0' encoding='UTF-8'?>
<entry xmlns='http://www.w3.org/2005/Atom'>
  <id>tag:example.com,2009:cmt-0.44775718</id>
  <author><name>test@example.com</name><uri>acct:test@example.com</uri>
  </author>
  <content>Salmon swim upstream!</content>
  <title>Salmon swim upstream!</title>
  <updated>2009-12-18T20:04:03Z</updated>
</entry>}."\n";

my $b64url_test_msg =<<'B64URL';
    PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0nVVRGLTgnPz4KPGVu
    dHJ5IHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20nPgog
    IDxpZD50YWc6ZXhhbXBsZS5jb20sMjAwOTpjbXQtMC40NDc3NTcxODwv
    aWQ-CiAgPGF1dGhvcj48bmFtZT50ZXN0QGV4YW1wbGUuY29tPC9uYW1l
    Pjx1cmk-YWNjdDp0ZXN0QGV4YW1wbGUuY29tPC91cmk-CiAgPC9hdXRo
    b3I-CiAgPGNvbnRlbnQ-U2FsbW9uIHN3aW0gdXBzdHJlYW0hPC9jb250
    ZW50PgogIDx0aXRsZT5TYWxtb24gc3dpbSB1cHN0cmVhbSE8L3RpdGxl
    PgogIDx1cGRhdGVkPjIwMDktMTItMThUMjA6MDQ6MDNaPC91cGRhdGVk
    Pgo8L2VudHJ5Pgo=
B64URL

$b64url_test_msg =~ tr{\t-\x0d }{}d;

is(b64url_encode($test_msg), $b64url_test_msg, 'Correct b64url encoded');

my $test_data_type = 'application/atom+xml';

use Mojolicious::Plugin::MagicSignatures::Envelope;
my $test_msg_base =
    Mojolicious::Plugin::MagicSignatures::Envelope::_sig_base($test_msg,
    $test_data_type);

my $exp_msg_base =<<'EXPMB';
    PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0nVVRGLTgnPz4KPGVu
    dHJ5IHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20nPgog
    IDxpZD50YWc6ZXhhbXBsZS5jb20sMjAwOTpjbXQtMC40NDc3NTcxODwv
    aWQ-CiAgPGF1dGhvcj48bmFtZT50ZXN0QGV4YW1wbGUuY29tPC9uYW1l
    Pjx1cmk-YWNjdDp0ZXN0QGV4YW1wbGUuY29tPC91cmk-CiAgPC9hdXRo
    b3I-CiAgPGNvbnRlbnQ-U2FsbW9uIHN3aW0gdXBzdHJlYW0hPC9jb250
    ZW50PgogIDx0aXRsZT5TYWxtb24gc3dpbSB1cHN0cmVhbSE8L3RpdGxl
    PgogIDx1cGRhdGVkPjIwMDktMTItMThUMjA6MDQ6MDNaPC91cGRhdGVk
    Pgo8L2VudHJ5Pgo=.
    YXBwbGljYXRpb24vYXRvbSt4bWw=.
    YmFzZTY0dXJs.
    UlNBLVNIQTI1Ng
EXPMB

$exp_msg_base =~ tr{\t-\x0d }{}d;

is($test_msg_base, $exp_msg_base, 'Correct signature base');

my $test_sig = 'RL3pTqRn7RAHoEKwtZCVDNgwHrNB0WJxFt8fq6l0HAGcIN4BLYzUC5hp'.
    'GySsnow2ibw3bgUVeiZMU0dPfrKBFA==';

my $real_sig = $mkey->sign($test_msg_base);

is($real_sig, $test_sig, 'Correct signature');










__END__

is(b64url_encode($test_msg), 'dGVzdCBzdHJpbmc=',
    'b64url correct');                             # 13

ok(b64url_encode($emsa) eq $test_emsa,
                     'Emsa correct');              # 14


__END__






$test_msg = "<?xml version='1.0' encoding='UTF-8'?>
<entry xmlns='http://www.w3.org/2005/Atom'>
<id>tag:example.com,2009:cmt-0.44775718</id>
<author><name>nils</name><uri>acct:nils.diewald@gmail.com</uri></author>
<title>Salmon swim upstream!</title>
</entry>";









$test_msg =    'test string';






# From https://github.com/sivy/Salmon/blob/master/t/30-magic-algorithms.t
my $test_sig = 'mNpBIpTUOESnuQMlS8aWZ4hwdS'.
               'wWnMstrn0F3L9GHDXa238fN3Bx'.
               '3Rl0yvVESM_eZuocLsp9ubUrYD'.
               'u83821fQ==';


my $sig = $mkey->sign($test_msg);
ok($sig eq $test_sig,  'Signature correct');       # 15

# https://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html

$test_msg = 'Not really Atom';
my $test_data_type = 'application/atom+xml';
my $test_base_sig = 'Tm90IHJlYWxseSBBdG9t.YXBwbGljYXRpb24vYXRvbSt4bWw=.'.
    'YmFzZTY0dXJs.UlNBLVNIQTI1Ng';







__END__

my $b64_test_msg =<<'TEST_DATA';
    PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0nVVRGLTgnPz4KPGVudHJ5IHhtbG5zPS
    dodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20nPgogIDxpZD50YWc6ZXhhbXBsZS5jb20s
    MjAwOTpjbXQtMC40NDc3NTcxODwvaWQ-ICAKICA8YXV0aG9yPjxuYW1lPnRlc3RAZXhhbX
    BsZS5jb208L25hbWUPHVyaT5hY2N0OmpwYW56ZXJAZ29vZ2xlLmNvbTwvdXJpPjwvYXV0a
    G9yPgogIDx0aHI6aW4tcmVwbHktdG8geG1sbnM6dGhyPSdodHRwOi8vcHVybC5vcmcvc3l
    uZGljYXRpb24vdGhyZWFkLzEuMCcKICAgICAgcmVmPSd0YWc6YmxvZ2dlci5jb20sMTk5O
    TpibG9nLTg5MzU5MTM3NDMxMzMxMjczNy5wb3N0LTM4NjE2NjMyNTg1Mzg4NTc5NTQnPnR
    hZzpibG9nZ2VyLmNvbSwxOTk5OmJsb2ctODkzNTkxMzc0MzEzMzEyNzM3LnBvc3QtMzg2M
    TY2MzI1ODUzODg1Nzk1NAogIDwvdGhyOmluLXJlcGx5LXRvPgogIDxjb250ZW50PlNhbG1
    vbiBzd2ltIHVwc3RyZWFtITwvY29udGVudD4KICA8dGl0bGUU2FsbW9uIHN3aW0gdXBzdH
    JlYW0hPC90aXRsZT4KICA8dXBkYXRlZD4yMDA5LTEyLTE4VDIwOjA0OjAzWjwvdXBkYXRl
    ZD4KPC9lbnRyeT4KICAgIA
TEST_DATA

$test_sig = 'EvGSD2vi8qYcveHnb-rrlok07qnCXjn8YSeCDDXlbhILSabgvNsPpbe76up8w63i2f
    WHvLKJzeGLKfyHg8ZomQ'



use Mojolicious::Plugin::MagicSignatures::Envelope;
my $test_msg_base =
    Mojolicious::Plugin::MagicSignatures::Envelope::_sig_base($test_msg);

ok($mkey->verify($test_msg_base, $test_sig), 'Signature okay.');








__END__

# https://salmon-playground.appspot.com/magicsigdemo
$test_msg = "<?xml version='1.0' encoding='UTF-8'?>
<entry xmlns='http://www.w3.org/2005/Atom'>
<id>tag:example.com,2009:cmt-0.44775718</id>
<author><name>nils</name><uri>acct:nils.diewald@gmail.com</uri></author>
<title>Salmon swim upstream!</title>
</entry>";

my $b64_test_msg = '
    PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0nVVRGLTgnPz4KPGVu
    dHJ5IHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20nPgo8
    aWQ-dGFnOmV4YW1wbGUuY29tLDIwMDk6Y210LTAuNDQ3NzU3MTg8L2lk
    Pgo8YXV0aG9yPjxuYW1lPm5pbHM8L25hbWU-PHVyaT5hY2N0Om5pbHMu
    ZGlld2FsZEBnbWFpbC5jb208L3VyaT48L2F1dGhvcj4KPHRpdGxlPlNh
    bG1vbiBzd2ltIHVwc3RyZWFtITwvdGl0bGU-CjwvZW50cnk-';

my $me_msg =
"<?xml version='1.0' encoding='UTF-8'?>
<me:env xmlns:me='http://salmon-protocol.org/ns/magic-env'>
  <me:encoding>base64url</me:encoding>
  <me:data type='application/atom+xml'>
    PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0nVVRGLTgnPz4KPGVu
    dHJ5IHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20nPgo8
    aWQ-dGFnOmV4YW1wbGUuY29tLDIwMDk6Y210LTAuNDQ3NzU3MTg8L2lk
    Pgo8YXV0aG9yPjxuYW1lPm5pbHM8L25hbWU-PHVyaT5hY2N0Om5pbHMu
    ZGlld2FsZEBnbWFpbC5jb208L3VyaT48L2F1dGhvcj4KPHRpdGxlPlNh
    bG1vbiBzd2ltIHVwc3RyZWFtITwvdGl0bGU-CjwvZW50cnk-
  </me:data>
  <me:alg>RSA-SHA256</me:alg>
  <me:sig>
    L_RuCJy419ENoy7yce7BqgVstkTPy1Qg32SeUxC8Lnx-nIeOx_fYjRQ4
    cVg1Snw91cWZFbGDAcsyWwTWCELzYA==
  </me:sig>
</me:env>";


# https://github.com/duck1123/jiksnu/blob/master/src/main/clojure/jiksnu/model/signature.clj

__END__


# https://github.com/eschnou/node-ostatus/blob/master/tests/test-salmon.js
# New signature:
$test_sig =<<'TEST_SIG';
UqKwh0XSOhdSD7U9nVHxB67sCNt8lQzkl5aPELQTfuh
rlBoktbExhhkP4QGFg0WS0FgPnQpG24z5S4XIk2BTjI
8My-VlwRWdeU72NtnLhZjz8EzA1aJTI_Drs71-YICuM
_dLAJgo55pF4nIMkRN9KA-rS-y7oC3cwt01MknR8UQ=
TEST_SIG

my $b64_test_msg =<<'TEST_MSG';
PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVR
GLTgiID8-PGVudHJ5IHhtbG5zPSJodHRwOi8vd3d3Ln
czLm9yZy8yMDA1L0F0b20iIHhtbG5zOnRocj0iaHR0c
DovL3B1cmwub3JnL3N5bmRpY2F0aW9uL3RocmVhZC8x
LjAiIHhtbG5zOmFjdGl2aXR5PSJodHRwOi8vYWN0aXZ
pdHlzdHJlYS5tcy9zcGVjLzEuMC8iIHhtbG5zOmdlb3
Jzcz0iaHR0cDovL3d3dy5nZW9yc3Mub3JnL2dlb3Jzc
yIgeG1sbnM6b3N0YXR1cz0iaHR0cDovL29zdGF0dXMu
b3JnL3NjaGVtYS8xLjAiIHhtbG5zOnBvY289Imh0dHA
6Ly9wb3J0YWJsZWNvbnRhY3RzLm5ldC9zcGVjLzEuMC
IgeG1sbnM6bWVkaWE9Imh0dHA6Ly9wdXJsLm9yZy9ze
W5kaWNhdGlvbi9hdG9tbWVkaWEiIHhtbG5zOnN0YXR1
c25ldD0iaHR0cDovL3N0YXR1cy5uZXQvc2NoZW1hL2F
waS8xLyI-CiA8YWN0aXZpdHk6b2JqZWN0LXR5cGU-aH
R0cDovL2FjdGl2aXR5c3RyZWEubXMvc2NoZW1hLzEuM
C9ub3RlPC9hY3Rpdml0eTpvYmplY3QtdHlwZT4KIDxp
ZD5odHRwOi8vaWRlbnRpLmNhL25vdGljZS82NTEzOTc
5MjwvaWQ-CiA8dGl0bGU-dGhpcyBvbmUgaXMgZm9yIE
BjYXBhQGVzY2hlbmF1ZXIuYmUgLSBlbmpveSAhPC90a
XRsZT4KIDxjb250ZW50IHR5cGU9Imh0bWwiPnRoaXMg
b25lIGlzIGZvciBAJmx0O3NwYW4gY2xhc3M9JnF1b3Q
7dmNhcmQmcXVvdDsmZ3Q7Jmx0O2EgaHJlZj0mcXVvdD
todHRwOi8vZXNjaGVuYXVlci5iZS91c2Vycy9jYXBhJ
nF1b3Q7IGNsYXNzPSZxdW90O3VybCZxdW90OyZndDsm
bHQ7c3BhbiBjbGFzcz0mcXVvdDtmbiBuaWNrbmFtZSZ
xdW90OyZndDtjYXBhQGVzY2hlbmF1ZXIuYmUmbHQ7L3
NwYW4mZ3Q7Jmx0Oy9hJmd0OyZsdDsvc3BhbiZndDsgL
SBlbmpveSAhPC9jb250ZW50PgogPGxpbmsgcmVsPSJh
bHRlcm5hdGUiIHR5cGU9InRleHQvaHRtbCIgaHJlZj0
iaHR0cDovL2lkZW50aS5jYS9ub3RpY2UvNjUxMzk3OT
IiLz4KIDxhY3Rpdml0eTp2ZXJiPmh0dHA6Ly9hY3Rpd
ml0eXN0cmVhLm1zL3NjaGVtYS8xLjAvcG9zdDwvYWN0
aXZpdHk6dmVyYj4KIDxwdWJsaXNoZWQ-MjAxMS0wMi0
yMlQyMToyMjo0OSswMDowMDwvcHVibGlzaGVkPgogPH
VwZGF0ZWQ-MjAxMS0wMi0yMlQyMToyMjo0OSswMDowM
DwvdXBkYXRlZD4KIDxhdXRob3I-CiAgPGFjdGl2aXR5
Om9iamVjdC10eXBlPmh0dHA6Ly9hY3Rpdml0eXN0cmV
hLm1zL3NjaGVtYS8xLjAvcGVyc29uPC9hY3Rpdml0eT
pvYmplY3QtdHlwZT4KICA8dXJpPmh0dHA6Ly9pZGVud
GkuY2EvdXNlci8zODUyMTY8L3VyaT4KICA8bmFtZT5z
aG91dHI8L25hbWU-CiAgPGxpbmsgcmVsPSJhbHRlcm5
hdGUiIHR5cGU9InRleHQvaHRtbCIgaHJlZj0iaHR0cD
ovL2lkZW50aS5jYS9zaG91dHIiLz4KICA8bGluayByZ
Ww9ImF2YXRhciIgdHlwZT0iaW1hZ2UvcG5nIiBtZWRp
YTp3aWR0aD0iOTYiIG1lZGlhOmhlaWdodD0iOTYiIGh
yZWY9Imh0dHA6Ly90aGVtZS5pZGVudGkuY2EvMC45Lj
diZXRhMi9pZGVudGljYS9kZWZhdWx0LWF2YXRhci1wc
m9maWxlLnBuZyIvPgogIDxsaW5rIHJlbD0iYXZhdGFy
IiB0eXBlPSJpbWFnZS9wbmciIG1lZGlhOndpZHRoPSI
0OCIgbWVkaWE6aGVpZ2h0PSI0OCIgaHJlZj0iaHR0cD
ovL3RoZW1lLmlkZW50aS5jYS8wLjkuN2JldGEyL2lkZ
W50aWNhL2RlZmF1bHQtYXZhdGFyLXN0cmVhbS5wbmci
Lz4KICA8bGluayByZWw9ImF2YXRhciIgdHlwZT0iaW1
hZ2UvcG5nIiBtZWRpYTp3aWR0aD0iMjQiIG1lZGlhOm
hlaWdodD0iMjQiIGhyZWY9Imh0dHA6Ly90aGVtZS5pZ
GVudGkuY2EvMC45LjdiZXRhMi9pZGVudGljYS9kZWZh
dWx0LWF2YXRhci1taW5pLnBuZyIvPgogIDxwb2NvOnB
yZWZlcnJlZFVzZXJuYW1lPnNob3V0cjwvcG9jbzpwcm
VmZXJyZWRVc2VybmFtZT4KICA8cG9jbzpkaXNwbGF5T
mFtZT5TaG91dHI8L3BvY286ZGlzcGxheU5hbWU-CiAg
PHBvY286dXJscz4KICAgPHBvY286dHlwZT5ob21lcGF
nZTwvcG9jbzp0eXBlPgogICA8cG9jbzp2YWx1ZT5odH
RwOi8vc2hvdXRyLm9yZzwvcG9jbzp2YWx1ZT4KICAgP
HBvY286cHJpbWFyeT50cnVlPC9wb2NvOnByaW1hcnk-
CjwvcG9jbzp1cmxzPgo8L2F1dGhvcj4KIDwhLS1EZXB
yZWNhdGlvbiB3YXJuaW5nOiBhY3Rpdml0eTphY3Rvci
BpcyBwcmVzZW50IG9ubHkgZm9yIGJhY2t3YXJkIGNvb
XBhdGliaWxpdHkuIEl0IHdpbGwgYmUgcmVtb3ZlZCBp
biB0aGUgbmV4dCB2ZXJzaW9uIG9mIFN0YXR1c05ldC4
tLT4KIDxhY3Rpdml0eTphY3Rvcj4KICA8YWN0aXZpdH
k6b2JqZWN0LXR5cGU-aHR0cDovL2FjdGl2aXR5c3RyZ
WEubXMvc2NoZW1hLzEuMC9wZXJzb248L2FjdGl2aXR5
Om9iamVjdC10eXBlPgogIDxpZD5odHRwOi8vaWRlbnR
pLmNhL3VzZXIvMzg1MjE2PC9pZD4KICA8dGl0bGU-U2
hvdXRyPC90aXRsZT4KICA8bGluayByZWw9ImFsdGVyb
mF0ZSIgdHlwZT0idGV4dC9odG1sIiBocmVmPSJodHRw
Oi8vaWRlbnRpLmNhL3Nob3V0ciIvPgogIDxsaW5rIHJ
lbD0iYXZhdGFyIiB0eXBlPSJpbWFnZS9wbmciIG1lZG
lhOndpZHRoPSI5NiIgbWVkaWE6aGVpZ2h0PSI5NiIga
HJlZj0iaHR0cDovL3RoZW1lLmlkZW50aS5jYS8wLjku
N2JldGEyL2lkZW50aWNhL2RlZmF1bHQtYXZhdGFyLXB
yb2ZpbGUucG5nIi8-CiAgPGxpbmsgcmVsPSJhdmF0YX
IiIHR5cGU9ImltYWdlL3BuZyIgbWVkaWE6d2lkdGg9I
jQ4IiBtZWRpYTpoZWlnaHQ9IjQ4IiBocmVmPSJodHRw
Oi8vdGhlbWUuaWRlbnRpLmNhLzAuOS43YmV0YTIvaWR
lbnRpY2EvZGVmYXVsdC1hdmF0YXItc3RyZWFtLnBuZy
IvPgogIDxsaW5rIHJlbD0iYXZhdGFyIiB0eXBlPSJpb
WFnZS9wbmciIG1lZGlhOndpZHRoPSIyNCIgbWVkaWE6
aGVpZ2h0PSIyNCIgaHJlZj0iaHR0cDovL3RoZW1lLml
kZW50aS5jYS8wLjkuN2JldGEyL2lkZW50aWNhL2RlZm
F1bHQtYXZhdGFyLW1pbmkucG5nIi8-CiAgPHBvY286c
HJlZmVycmVkVXNlcm5hbWU-c2hvdXRyPC9wb2NvOnBy
ZWZlcnJlZFVzZXJuYW1lPgogIDxwb2NvOmRpc3BsYXl
OYW1lPlNob3V0cjwvcG9jbzpkaXNwbGF5TmFtZT4KIC
A8cG9jbzp1cmxzPgogICA8cG9jbzp0eXBlPmhvbWVwY
WdlPC9wb2NvOnR5cGU-CiAgIDxwb2NvOnZhbHVlPmh0
dHA6Ly9zaG91dHIub3JnPC9wb2NvOnZhbHVlPgogICA
8cG9jbzpwcmltYXJ5PnRydWU8L3BvY286cHJpbWFyeT
4KPC9wb2NvOnVybHM-CjwvYWN0aXZpdHk6YWN0b3I-C
iA8bGluayByZWw9Im9zdGF0dXM6Y29udmVyc2F0aW9u
IiBocmVmPSJodHRwOi8vaWRlbnRpLmNhL2NvbnZlcnN
hdGlvbi82NDM4Mjk1NSIvPgogPGxpbmsgcmVsPSJvc3
RhdHVzOmF0dGVudGlvbiIgaHJlZj0iaHR0cDovL2VzY
2hlbmF1ZXIuYmUvdXNlcnMvY2FwYSIvPgogPGxpbmsg
cmVsPSJtZW50aW9uZWQiIGhyZWY9Imh0dHA6Ly9lc2N
oZW5hdWVyLmJlL3VzZXJzL2NhcGEiLz4KIDxnZW9yc3
M6cG9pbnQ-NTAuNTY2NjcgNS41ODMzMzwvZ2VvcnNzO
nBvaW50PgogPHNvdXJjZT4KICA8aWQ-aHR0cDovL2Vz
Y2hlbmF1ZXIuYmUvdXBkYXRlcy9jYXBhLmF0b208L2l
kPgogIDx0aXRsZT5jYXBhPC90aXRsZT4KICA8bGluay
ByZWw9ImFsdGVybmF0ZSIgdHlwZT0idGV4dC9odG1sI
iBocmVmPSJodHRwOi8vZXNjaGVuYXVlci5iZS91c2Vy
cy9jYXBhIi8-CiAgPGxpbmsgcmVsPSJzZWxmIiB0eXB
lPSJhcHBsaWNhdGlvbi9hdG9tK3htbCIgaHJlZj0iaH
R0cDovL2VzY2hlbmF1ZXIuYmUvdXBkYXRlcy9jYXBhL
mF0b20iLz4KICA8aWNvbj5odHRwOi8vdGhlbWUuaWRl
bnRpLmNhLzAuOS43YmV0YTIvaWRlbnRpY2EvZGVmYXV
sdC1hdmF0YXItcHJvZmlsZS5wbmc8L2ljb24-Cjwvc2
91cmNlPgogPGxpbmsgcmVsPSJzZWxmIiB0eXBlPSJhc
HBsaWNhdGlvbi9hdG9tK3htbCIgaHJlZj0iaHR0cDov
L2lkZW50aS5jYS9hcGkvc3RhdHVzZXMvc2hvdy82NTE
zOTc5Mi5hdG9tIi8-CiA8bGluayByZWw9ImVkaXQiIH
R5cGU9ImFwcGxpY2F0aW9uL2F0b20reG1sIiBocmVmP
SJodHRwOi8vaWRlbnRpLmNhL2FwaS9zdGF0dXNlcy9z
aG93LzY1MTM5NzkyLmF0b20iLz4KIDxzdGF0dXNuZXQ
6bm90aWNlX2luZm8gbG9jYWxfaWQ9IjY1MTM5NzkyIi
Bzb3VyY2U9IndlYiI-PC9zdGF0dXNuZXQ6bm90aWNlX
2luZm8-CjwvZW50cnk-Cg==
TEST_MSG

$test_msg = b64url_decode($b64_test_msg);
my $data_type = 'application/atom xml',

$test_public_key =<<'TEST_PKEY';
RSA.iuv17d7U1uJxgDbCt1nEtaIbKAmV02MWIQLubaW
Dc4juUBmdvbY1ms0EtFhrYLSK1j3kyqysM7vqjj-DYD
bq2NPQpUrq2DFqj7Y2b8PG4-Dj6KUPDmkVRa-ZFo63B
WX6US5Vsi31HHFh_rku1OPdPrHjQhtN8HeFYnNBpd4U
AA0=.AQAB
TEST_PKEY

$mkey = Mojolicious::Plugin::MagicSignatures::Key->new($test_public_key);


ok($mkey->verify($b64_test_msg, $test_sig), 'Signature okay.');


__END__

SKIP: {
    skip 'Not working', 1;
    $mkey->d( undef ); # Delete private part

};
