package Mojolicious::Plugin::WebFinger;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

# Register Plugin
sub register {
  my ($plugin, $mojo) = @_;

  # This is a modern version of Webfinger
  # without LRDD

  my $wfr = $mojo->routes->route('/.well-known/webfinger');

  # Establish endpoint
  $wfr->endpoint(
    webfinger => {
      query => [
	'resource' => '{uri}',
	'rel'      => '{rel?}',
	'format'   => '{format?}'
      ]
    }
  );

  $wfr->to(
    cb => sub {
      my $c = shift;
      my $res = $c->stash('resource');

      # Bad request
      return $c->render(status => 400) unless $res;

      if ($c->callback(prepare_webfinger => $res)) {
	return if $c->res->body;

	return $c->render_xrd($plugin->_serve($c, $uri), $uri);
      };

      return $c->render_xrd(undef => $res);
    }
  );


  # Add Route to Hostmeta - exactly once
  $mojo->hook(
    on_prepare_hostmeta => sub {

      # Todo: Do not pass plugin
      my ($hm_plugin, $c, $hostmeta) = @_;

      # Add XRD link
      $hostmeta->add_link( lrdd => {
	type     => 'application/xrd+xml',
	template => $c->endpoint(
	  webfinger => {
	    format => 'xrd'
	  }
	)
      })->comment('Webfinger (XRD)');

      # Add JRD link
      $hostmeta->add_link( lrdd => {
	type     => 'application/jrd+json',
	template => $c->endpoint(
	  webfinger => {
	    format => 'jrd'
	  }
	)
      })->comment('Webfinger (JRD)');
    });
};


1;

__END__




See http://www.packetizer.com/webfinger/server.html
See: https://tools.ietf.org/html/draft-ietf-appsawg-webfinger-10
   establish /.well-known/webfinger?resource=acct:bob@example.com
   Access-Control-Allow-Origin: *
   Content-Type: application/jrd+json; charset=UTF-8

jrd-only

 Idee: In host-meta wird der Link mit einem Template und einem Flag angegeben, bei dem Primär xrd zurückgegeben wird und nicht jrd, ansonsten wird bei der direkten well-known geschichte jrd zurückgegeben

 If the "resource" parameter is absent or malformed, the WebFinger server MUST return a 400 status code.

 Accept-Handler kann auch xrd fordern

# jrd:
# - subject
# - aliases
# - properties
# - links

 Im Hostmeta:
 rel : 'lrdd', type: 'xrd ... ?', template : 'https://example.com/.well-known/webfinger?resource={uri}&rel={rel?}&format=xml'
 rel : 'lrdd', type: 'application/jrd+json', template : 'https://example.com/.well-known/webfinger?resource={uri}&rel={rel?}format=json'

multiple rels are allowed!
$c->webfinger('acct:bob@example.com' => [rel,rel]);

# Maybe support accepting parameters "principal" (from SWD) and "subject" as well ...
