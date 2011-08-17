package Mojolicious::Plugin::Atom::Pub;
use Mojo::Base 'Mojolicious::Plugin';

# Register Plugin
sub register {
    my ($plugin, $mojo) = @_;

    unless (exists $mojo->renderer->helpers->{'atom'}) {
	$mojo->plugin('Atom');
    };

    my $routes = $mojo->routes;

    # Add 'atom' condition
    $routes->add_condition(
	'atom' => sub {
	    my ($r, $c) = @_;
	    my $atom = $c->new_atom( $c->req->body );
	    if ($atom->at('entry')) {
		$c->stash('plugin.atom' => $atom);
		return 1;
	    };
	    return;
	});

    # Add 'atom' shortcut
    $routes->add_shortcut(
	'atom' => sub {
	    my $route = shift;
	    my @param = @_;

	    # PostURI
	    $route->post('/PostURI')
                  ->over('atom')
                  ->to('action' => 'post', @param);

	    # EditURI
	    my $edit = $route->route('/EditURI');

	    # EditURI - get
	    $edit->via('get')
		 ->to('action' => 'get_entry', @param);

	    # EditURI - put
	    $edit->via('put')->over('atom')
                  ->to('action' => 'put_entry', @param);

	    # EditURI - delete
	    $edit->via('delete')->over('atom')
                  ->to('action' => 'delete_entry', @param);

	    # FeedURI
	    $route->get('/FeedURI')
		  ->to('action' => 'get_feed', @param);

	    return $route;

	});
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::Atom::Pub;

=head1 SYNOPSIS

=head1 CONDITIONS

=head2 C<atom>

    # Mojolicious
    $r->over('atom')->to(cb => sub { shift->render_text('Atom!') } );

    # Mojolicious::Lite

This condition fails, if no Atom feed or entry is passed in the post body
of a request. If the condition is passed, the Atom feed or entry is parsed
into an L<Mojolicious::Plugin::Atom::Document> object and stashed in
C<plugin.atom>.


SHORTCUTS
  atom

    $r->route('MyAtomFeed')->atom(controller => 'my_controller');

This shortcut establishes the Atom API under the given route.
The associated controller can have the following actions:

  get_feed
    GET FeedURI

  get_entry
    GET EditURI

  delete_entry
    DELETE EditURI
    The Atom object is in C<plugin.atom>.


  put_entry
    PUT EditURI
    The Atom object is in C<plugin.atom>.

  post_entry
    POST PostURI
    The Atom object is in C<plugin.atom>.
