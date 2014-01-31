use Test::More tests => 1; # temp
use Test::Mojo;
use strict;
use warnings;
$|++;

use lib '../lib';

use_ok('Mojolicious::Plugin::MagicSignatures');

__END__

use Mojolicious::Lite;
use Mojo::ByteStream 'b';

my $t = Test::Mojo->new;

my $app = $t->app;

$app->plugin('magic_signatures');

# Silence
app->log->level('error');

$app->defaults(
    key => 'RSA.'.
    'mVgY8RN6URBTstndvmUUPb4UZTdwvw'.
    'mddSKE5z_jvKUEK6yk1u3rrC9yN8k6'.
    'FilGj9K0eeUPe2hf4Pj-5CmHww==.'.
    'AQAB.'.
    'Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6'.
    'yihYetQ8jy-jZXdsZXd8V5ub3kuBHH'.
    'k4M39i3TduIkcrjcsiWQb77D8Q=='
);

get '/me' => sub {
    my $self = shift;
    my $me = $self->magicenvelope( {
	data_type => $self->param('data_type'),
	data      => $self->param('data')
				   } );
    $me->sign( { key => $self->stash('key') } );

    # Return JSON
    if ($self->param('format') eq 'json') {
	return $self->render(
	    'format' => 'me-json',
	    'data' => $me->to_json
	    );
    }

    # Return XML
    elsif ($self->param('format') eq 'xml') {
	return $self->render(
	    'format' => 'me-xml',
	    'data' => $me->to_xml
	    );
    }

    # Return Compact
    elsif ($self->param('format') eq 'compact') {
	return $self->render(
	    'format' => 'text/plain',
	    'data' => $me->to_compact
	    );
    };
};

my $test_string = 'test string';

my $retc = {
    data_type => 'text/plain',
    sigs => [
	{ key_id => undef,
	  value => 'Ykw1OVdWaEhRc05jUFVWdU42UFU4X'.
	           '1N6UTdmdW9XSjlaU19ZQUxILXFUS3'.
		   'RwU3gzcmdFY3VEek5TWS0zY3d5TGh'.
		   'rbW1qMk9WdkN4U2RQUFM2TzhJNHc9'.
		   'PQ=='
	}
	],
    data => 'dGVzdCBzdHJpbmc=',
    alg => 'RSA-SHA256',
    encoding => 'base64url'
};

my $request = '/me?data_type=text/plain&data='.b($test_string)->url_escape;

# Check json response
$t->get_ok($request.'&format=json')
    ->status_is(200)->json_content_is($retc);

# Check xml response
my $res = $t->ua->get($request.'&format=xml')->res;

ok($res->is_status_class(200), 'XML - Correct return');

my $sig = $res->dom->find('sig')->[0]->text;
$sig =~ s/[\s\n]+//g;

ok($sig eq $retc->{sigs}->[0]->{value},
   'XML - Sig is correct');

# Check compact response
my $compact_result = '.Ykw1OVdWaEhRc05jUFVWd'.
    'U42UFU4X1N6UTdmdW9XSjlaU19ZQUxILXFUS3Rw'.
    'U3gzcmdFY3VEek5TWS0zY3d5TGhrbW1qMk9WdkN'.
    '4U2RQUFM2TzhJNHc9PQ==.dGVzdCBzdHJpbmc.d'.
    'GV4dC9wbGFpbg.YmFzZTY0dXJs.UlNBLVNIQTI1'.
    'Ng';

$t->get_ok($request.'&format=compact')
    ->status_is(200)->content_is($compact_result);

__END__
