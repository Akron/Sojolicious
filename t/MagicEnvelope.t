#!/usr/bin/env perl
use Test::More tests => 13;
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

$me->sign($mkey_string);

ok($me->signed, 'Envelope signed');

my $mkey = Mojolicious::Plugin::MagicSignatures::Key->new(<<'MKEY');
  RSA.
  mVgY8RN6URBTstndvmUUPb4UZTdwvw
  mddSKE5z_jvKUEK6yk1u3rrC9yN8k6
  FilGj9K0eeUPe2hf4Pj-5CmHww==.
  AQAB
MKEY

ok($me->verify( [ [ $mkey ] ] ), 'MagicEnvelope Verification');

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
  'Compact serialization');


###############
# From MiniMe #

$mkey = Mojolicious::Plugin::MagicSignatures::Key->new(<<'MKEY');
RSA.hkwS0EK5Mg1dpwA4shK5FNtHmo9F7sIP6gKJ5fyFWNotObbbckq4dk4dhldMKF42b2FPsci109MF7NsdNYQ0kXd3jNs9VLCHUujxiafVjhw06hFNWBmvptZud7KouRHz4Eq2sB-hM75MEn3IJElOquYzzUHi7Q2AMalJvIkG26c=.AQAB.JrT8YywoBoYVrRGCRcjhsWI2NBUBWfxy68aJilEK-f4ANPdALqPcoLSJC_RTTftBgz6v4pTv2zqiJY9NzuPo5mijN4jJWpCA-3HOr9w8Kf8uLwzMVzNJNWD_cCqS5XjWBwWTObeMexrZTgYqhymbfxxz6Nqxx352oPh4vycnXOk=
MKEY

my $sig = 'aMMmGLJd81bgBdU26WjVCT1zIH17ND0dlfArs1Kii_fVYFyz6IEyQzM3GddvzAfJ51vo-uN_RY9TEHtoHp12N9Abg9AbCcrPcBGvcP7VBhFWw857v_sYlbD6nek9cX9JKBu-C_Xf20QGuE5dPFL0S4kZsuemeQ8p6cJAj_RbumM=';

$me = Mojolicious::Plugin::MagicSignatures::Envelope->new(<<'ME');
<?xml version="1.0" encoding="UTF-8"?>
<me:env xmlns:me="http://salmon-protocol.org/ns/magic-env">
  <me:data type="application/atom+xml">PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPGVudHJ5IHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20iIHhtbG5zOmFjdGl2aXR5PSJodHRwOi8vYWN0aXZpdHlzdHJlYS5tcy9zcGVjLzEuMC8iPgogIDxpZD5taW1pbWU6MTIzNDU2ODk8L2lkPgogIDx0aXRsZT5UdW9tYXMgaXMgbm93IGZvbGxvd2luZyBQYW1lbGEgQW5kZXJzb248L3RpdGxlPgogIDxjb250ZW50IHR5cGU9InRleHQvaHRtbCI-VHVvbWFzIGlzIG5vdyBmb2xsb3dpbmcgUGFtZWxhIEFuZGVyc29uPC9jb250ZW50PgogIDx1cGRhdGVkPjIwMTAtMDctMjZUMDY6NDI6NTUrMDI6MDA8L3VwZGF0ZWQ-CiAgPGF1dGhvcj4KICAgIDx1cmk-aHR0cDovL2xvYnN0ZXJtb25zdGVyLm9yZy90dW9tYXM8L3VyaT4KICAgIDxuYW1lPlR1b21hcyBLb3NraTwvbmFtZT4KICA8L2F1dGhvcj4KICA8YWN0aXZpdHk6YWN0b3I-CiAgICA8YWN0aXZpdHk6b2JqZWN0LXR5cGU-aHR0cDovL2FjdGl2aXR5c3RyZWEubXMvc2NoZW1hLzEuMC9wZXJzb248L2FjdGl2aXR5Om9iamVjdC10eXBlPgogICAgPGlkPnR1b21hc0Bsb2JzdGVybW9uc3Rlci5vcmc8L2lkPgogICAgPHRpdGxlPlR1b21hcyBLb3NraTwvdGl0bGU-CiAgICA8bGluayByZWY9ImFsdGVybmF0ZSIgdHlwZT0idGV4dC9odG1sIiBocmVmPSJodHRwOi8vaWRlbnRpLmNhL3Rrb3NraSIvPgogIDwvYWN0aXZpdHk6YWN0b3I-CiAgPGFjdGl2aXR5OnZlcmI-aHR0cDovL2FjdGl2aXR5c3RyZWEubXMvc2NoZW1hLzEuMC9mb2xsb3c8L2FjdGl2aXR5OnZlcmI-CjwvZW50cnk-Cg==</me:data>
  <me:encoding>base64url</me:encoding>
  <me:alg>RSA-SHA256</me:alg>
  <me:sig>aMMmGLJd81bgBdU26WjVCT1zIH17ND0dlfArs1Kii_fVYFyz6IEyQzM3GddvzAfJ51vo-uN_RY9TEHtoHp12N9Abg9AbCcrPcBGvcP7VBhFWw857v_sYlbD6nek9cX9JKBu-C_Xf20QGuE5dPFL0S4kZsuemeQ8p6cJAj_RbumM=</me:sig>
</me:env>
ME

ok($me->verify( [ [ $mkey ] ] ), 'MiniMe Verification');

$me->{sigs} = [];
$me->sign($mkey);

is ($me->signature->{value}, $sig, 'MiniMe Signature');

$mkey = Mojolicious::Plugin::MagicSignatures::Key->new(<<'IDENTICAKEY');
RSA.oSdSbJ99WDC0zRUpk41bpI42FarMo-o6JxJKEeKCPSU1SW9kdXdAUPhWu0JVwdF5rDXWijXaOcdZ3utGwk0pmKxsX6MEQg54L4rfIzWZiHz9OUGgDx9R4tXpm38CXOGfpu4Sx2lmeYVxIii32P32EPJHyZN5Zi9Sr_8zSbXYnM8=.AQAB
IDENTICAKEY

$me = Mojolicious::Plugin::MagicSignatures::Envelope->new(<<'IDENTICA');
<?xml version="1.0"?>
<me:env xmlns:me="http://salmon-protocol.org/ns/magic-env">
  <me:data type="application/atom+xml">
    PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiID8-PGVudHJ5IHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20iIHhtbG5zOmFjdGl2aXR5PSJodHRwOi8vYWN0aXZpdHlzdHJlYS5tcy9zcGVjLzEuMC8iIHhtbG5zOmdlb3Jzcz0iaHR0cDovL3d3dy5nZW9yc3Mub3JnL2dlb3JzcyIgeG1sbnM6b3N0YXR1cz0iaHR0cDovL29zdGF0dXMub3JnL3NjaGVtYS8xLjAiIHhtbG5zOnBvY289Imh0dHA6Ly9wb3J0YWJsZWNvbnRhY3RzLm5ldC9zcGVjLzEuMCIgeG1sbnM6bWVkaWE9Imh0dHA6Ly9wdXJsLm9yZy9zeW5kaWNhdGlvbi9hdG9tbWVkaWEiPgogPGlkPnRhZzppZGVudGkuY2EsMjAxMC0wOC0xMDp1cGRhdGUtcHJvZmlsZTo1MjQ2NzoxOTcwLTAxLTAxVDAwOjAwOjAwKzAwOjAwPC9pZD4KIDx0aXRsZT5Qcm9maWxlIHVwZGF0ZTwvdGl0bGU-CiA8cHVibGlzaGVkPjE5NzAtMDEtMDFUMDA6MDA6MDArMDA6MDA8L3B1Ymxpc2hlZD4KIDxjb250ZW50IHR5cGU9Imh0bWwiPlR1b21hcyBLb3NraSBoYXMgdXBkYXRlZCB0aGVpciBwcm9maWxlIHBhZ2UuPC9jb250ZW50PgogPGF1dGhvcj4KICA8dXJpPmh0dHA6Ly9pZGVudGkuY2EvdXNlci81MjQ2NzwvdXJpPgogIDxuYW1lPlR1b21hcyBLb3NraTwvbmFtZT4KPC9hdXRob3I-CjxhY3Rpdml0eTphY3Rvcj4KIDxhY3Rpdml0eTpvYmplY3QtdHlwZT5odHRwOi8vYWN0aXZpdHlzdHJlYS5tcy9zY2hlbWEvMS4wL3BlcnNvbjwvYWN0aXZpdHk6b2JqZWN0LXR5cGU-CiA8aWQ-aHR0cDovL2lkZW50aS5jYS91c2VyLzUyNDY3PC9pZD4KIDx0aXRsZT5UdW9tYXMgS29za2k8L3RpdGxlPgogPGxpbmsgcmVsPSJhbHRlcm5hdGUiIHR5cGU9InRleHQvaHRtbCIgaHJlZj0iaHR0cDovL2lkZW50aS5jYS90a29za2kiLz4KIDxsaW5rIHJlbD0iYXZhdGFyIiB0eXBlPSJpbWFnZS9qcGVnIiBtZWRpYTp3aWR0aD0iMjY2IiBtZWRpYTpoZWlnaHQ9IjI2NiIgaHJlZj0iaHR0cDovL2F2YXRhci5pZGVudGkuY2EvNTI0NjctMjY2LTIwMTAwODEwMTMzMjIxLmpwZWciLz4KIDxsaW5rIHJlbD0iYXZhdGFyIiB0eXBlPSJpbWFnZS9qcGVnIiBtZWRpYTp3aWR0aD0iOTYiIG1lZGlhOmhlaWdodD0iOTYiIGhyZWY9Imh0dHA6Ly9hdmF0YXIuaWRlbnRpLmNhLzUyNDY3LTk2LTIwMTAwODEwMTMzMjIxLmpwZWciLz4KIDxsaW5rIHJlbD0iYXZhdGFyIiB0eXBlPSJpbWFnZS9qcGVnIiBtZWRpYTp3aWR0aD0iNDgiIG1lZGlhOmhlaWdodD0iNDgiIGhyZWY9Imh0dHA6Ly9hdmF0YXIuaWRlbnRpLmNhLzUyNDY3LTQ4LTIwMTAwODEwMTMzMjIxLmpwZWciLz4KIDxsaW5rIHJlbD0iYXZhdGFyIiB0eXBlPSJpbWFnZS9qcGVnIiBtZWRpYTp3aWR0aD0iMjQiIG1lZGlhOmhlaWdodD0iMjQiIGhyZWY9Imh0dHA6Ly9hdmF0YXIuaWRlbnRpLmNhLzUyNDY3LTI0LTIwMTAwODEwMTMzMjIyLmpwZWciLz4KPHBvY286cHJlZmVycmVkVXNlcm5hbWU-dGtvc2tpPC9wb2NvOnByZWZlcnJlZFVzZXJuYW1lPgo8cG9jbzpkaXNwbGF5TmFtZT5UdW9tYXMgS29za2k8L3BvY286ZGlzcGxheU5hbWU-Cjxwb2NvOm5vdGU-SGFwcHkgRmlubmlzaCBwcm9ncmFtbWVyLjwvcG9jbzpub3RlPgo8cG9jbzphZGRyZXNzPgogPHBvY286Zm9ybWF0dGVkPlBhcmlzPC9wb2NvOmZvcm1hdHRlZD4KPC9wb2NvOmFkZHJlc3M-Cjxwb2NvOnVybHM-CiA8cG9jbzp0eXBlPmhvbWVwYWdlPC9wb2NvOnR5cGU-CiA8cG9jbzp2YWx1ZT5odHRwOi8vd3d3LmxvYnN0ZXJtb25zdGVyLm9yZzwvcG9jbzp2YWx1ZT4KIDxwb2NvOnByaW1hcnk-dHJ1ZTwvcG9jbzpwcmltYXJ5Pgo8L3BvY286dXJscz4KPC9hY3Rpdml0eTphY3Rvcj4KIDxhY3Rpdml0eTp2ZXJiPmh0dHA6Ly9vc3RhdHVzLm9yZy9zY2hlbWEvMS4wL3VwZGF0ZS1wcm9maWxlPC9hY3Rpdml0eTp2ZXJiPgo8L2VudHJ5Pgo=
  </me:data>
  <me:encoding>base64url</me:encoding>
  <me:alg>RSA-SHA256</me:alg>
  <me:sig>FdN0qsIYyc_WtNCca0KMQx2YesT4jfNULkH5wMF6uJE1dwd74_2xEh559xAvnB-siPcdDbZAUb84z7hFSbtEBfbcYmM7PZAfZQFXHM-aXomqx0mXjRnRM2YKxO6l3FCd_enErW2q8E-hDE24FACdEK6LzbJnXFoRxMCYsW8l_jA=</me:sig>
</me:env>
IDENTICA

#warn $me->sig_base;
ok($me->verify( [ [ $mkey ] ] ), 'Identica Verification');

#############################
# From MagicSignatures Spec #

$mkey = Mojolicious::Plugin::MagicSignatures::Key->new(<<'MESPECKEY');
RSA.mVgY8RN6URBTstndvmUUPb4UZTdwvwmddSKE5z_jvKUEK6yk1u3rrC9yN8k6FilGj9K0eeUPe2hf4Pj-5CmHww.AQAB
MESPECKEY

$me = Mojolicious::Plugin::MagicSignatures::Envelope->new(<<'MESPEC');
<?xml version='1.0' encoding='UTF-8'?>
<me:env xmlns:me='http://salmon-protocol.org/ns/magic-env'>
  <me:data type='application/atom+xml'>
    PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0nVVRGLTgnPz4KPGVudHJ5IHhtbG5zPS
    dodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20nPgogIDxpZD50YWc6ZXhhbXBsZS5jb20s
    MjAwOTpjbXQtMC40NDc3NTcxODwvaWQ-ICAKICA8YXV0aG9yPjxuYW1lPnRlc3RAZXhhbX
    BsZS5jb208L25hbWU-PHVyaT5hY2N0OmpwYW56ZXJAZ29vZ2xlLmNvbTwvdXJpPjwvYXV0a
    G9yPgogIDx0aHI6aW4tcmVwbHktdG8geG1sbnM6dGhyPSdodHRwOi8vcHVybC5vcmcvc3l
    uZGljYXRpb24vdGhyZWFkLzEuMCcKICAgICAgcmVmPSd0YWc6YmxvZ2dlci5jb20sMTk5O
    TpibG9nLTg5MzU5MTM3NDMxMzMxMjczNy5wb3N0LTM4NjE2NjMyNTg1Mzg4NTc5NTQnPnR
    hZzpibG9nZ2VyLmNvbSwxOTk5OmJsb2ctODkzNTkxMzc0MzEzMzEyNzM3LnBvc3QtMzg2M
    TY2MzI1ODUzODg1Nzk1NAogIDwvdGhyOmluLXJlcGx5LXRvPgogIDxjb250ZW50PlNhbG1
    vbiBzd2ltIHVwc3RyZWFtITwvY29udGVudD4KICA8dGl0bGU-U2FsbW9uIHN3aW0gdXBzdH
    JlYW0hPC90aXRsZT4KICA8dXBkYXRlZD4yMDA5LTEyLTE4VDIwOjA0OjAzWjwvdXBkYXRl
    ZD4KPC9lbnRyeT4KICAgIA
  </me:data>
  <me:encoding>base64url</me:encoding>
  <me:alg>RSA-SHA256</me:alg>
  <me:sig key_id="4k8ikoyC2Xh+8BiIeQ+ob7Hcd2J7/Vj3uM61dy9iRMI=">
    EvGSD2vi8qYcveHnb-rrlok07qnCXjn8YSeCDDXlbhILSabgvNsPpbe76up8w63i2f
    WHvLKJzeGLKfyHg8ZomQ
  </me:sig>
</me:env>
MESPEC

ok($me->verify( [ [ $mkey ] ] ), 'MagicSignatures Spec Verification');

########################
# From Cliqset Example #
# https://code.google.com/p/java-salmon/source/browse/trunk/java-salmon-examples/src/main/java/com/cliqset/salmon/examples/SimpleSalmonVerify.java

$mkey = Mojolicious::Plugin::MagicSignatures::Key->new(<<'CLIQSETKEY');
RSA.oidnySWI_e4OND41VHNtYSRzbg5SaZ0YwnQ0J1ihKFEHY49-61JFybnszkSaJJD7vBfxyVZ1lTJjxdtBJzSNGEZlzKbkFvcMdtln8g2ec6oI2G0jCsjKQtsH57uHbPY3IAkBAW3Ar14kGmOKwqoGUq1yhz93rXUomLnDYwz8E88=.AQAB.hgOzTxbqhZN9wce4I7fSKnsJu2eyzP69O9j2UZ56cuulA6_Q4YP5kaNMB53DF32L0ASqHBCM1WXz984hptlT0e4U3asXxqegTqrGPNAXw5A6r2E-9MeS84LDFUnUz420YPxMxknzMJBeAz21PuKyrv_QZf6zmRQ0m5eQ0QNJoYE=
CLIQSETKEY

$sig = 'psinLK6mpn8IPrKRpta06m49dr2XggN6Bjkbnp3wLwEHClmgwBkwk4Q-3BGbEFxsCR0ogCiTj5JKZbkeR3IkK9bKlEYjMAXWLlrBkDKhfyOitdTbqcCREnd9tRqh562kCF84JY3m1NxPCU1MovMq0zUqryVytAZmgQoEPdzy3Ug=';

$me = Mojolicious::Plugin::MagicSignatures::Envelope->new(<<'CLIQSET');
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<env xmlns="http://salmon-protocol.org/ns/magic-env">
  <data type="application/atom+xml">
    PGVudHJ5IHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20iPg0KCTxpZD50YWc6cmV0aWN1bGF0ZW1lLmFwcHNwb3QuY29tLDIwMTAtMTEtMDY6L3NhbG1vbmxpYi9lbnRyeS8wQTBHZFE2cmJpYjdRZ3RfZjE5UTdiUE5hRWVxUVh6NXhNb2FfamN1Ti1BPC9pZD4NCgk8cHVibGlzaGVkPjIwMTAtMTEtMDZUMDE6NDY6NTEuMTQ3WjwvcHVibGlzaGVkPg0KCTx1cGRhdGVkPjIwMTAtMTEtMDZUMDE6NDY6NTEuMTQ3WjwvdXBkYXRlZD4NCgk8c3VtbWFyeSB0eXBlPSJodG1sIj5oZXksIHNvIGhlcmUgaXMgdGhlIHN1bW1hcnk8L3N1bW1hcnk-DQoJPHRpdGxlIHR5cGU9InRleHQiPmhleSwgc28gaGVyZSBpcyB0aGUgdGl0bGU8L3RpdGxlPg0KCTxsaW5rIGhyZWY9Imh0dHA6Ly9yZXRpY3VsYXRlbWUuYXBwc3BvdC5jb20vc2FsbW9ubGliL2VudHJ5LzBBMEdkUTZyYmliN1FndF9mMTlRN2JQTmFFZXFRWHo1eE1vYV9qY3VOLUEiIHR5cGU9InRleHQveGh0bWwiIHJlbD0iYWx0ZXJuYXRlIi8-DQoJPGF1dGhvcj4NCgkJPG5hbWU-U2FsbW9uIExpYnJhcnk8L25hbWU-DQoJCTx1cmk-YWNjdDpzYWxtb25saWJAcmV0aWN1bGF0ZW1lLmFwcHNwb3QuY29tPC91cmk-DQoJPC9hdXRob3I-DQo8L2VudHJ5Pg0KCQkJ
  </data>
  <encoding>base64url</encoding>
  <alg>RSA-SHA256</alg>
  <sig>psinLK6mpn8IPrKRpta06m49dr2XggN6Bjkbnp3wLwEHClmgwBkwk4Q-3BGbEFxsCR0ogCiTj5JKZbkeR3IkK9bKlEYjMAXWLlrBkDKhfyOitdTbqcCREnd9tRqh562kCF84JY3m1NxPCU1MovMq0zUqryVytAZmgQoEPdzy3Ug=</sig>
</env>
CLIQSET

ok($me->verify( [ [ $mkey ] ] ), 'Cliqset Verification');

$me->{sigs} = [];
$me->sign($mkey);

is ($me->signature->{value}, $sig, 'Cliqset Signature');

__END__
