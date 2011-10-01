package Mojolicious::Plugin::OStatus;
use Mojo::Base 'Mojolicious::Plugin';

# Register plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  my %default = (
    'host' => $param->{'host'}     || 'localhost',
    'secure' => $param->{'secure'} || 0
  );

  my $helpers = $mojo->renderer->helpers;

  foreach (qw/HostMeta
	      Webfinger
	      MagicSignatures
	      Salmon
	      PubSubHubbub
	      PortableContacts/) {

    $param->{ $_ } = +{} unless exists $param->{ $_ };
    $mojo->plugin($_ => { %default, %{ $param->{ $_ } } } );
  };

  $mojo->plugin('XML' => {
    new_ostatus => ['Atom',
		    'ActivityStreams',
		    'Atom-Threading',
		    'OStatus'] # PortableContacts
  });
};

1;

__END__

sub subscribe {
    my $self = shift;
    my $user = $self->stash('poco_user');

    # No actor given! err_str()?
    return unless $user;

    # User, Group, or Feed
    my $uri = shift;

    my $object;
    # direct feed
    if (index($uri, 'http') == 0) {
	# atom / xrd
	# html
	# $self->pubsub_subscribe();
    }

    # Webfinger
    elsif (index($uri,'@') >= 0) {
	my $wf_xrd = $self->webfinger( $uri );
    my $hub = $wf_xrd->get_link('hub');
    
    return unless $hub;

    $wf_xrd->get_link('http://schemas.google.com/g/2010#updates-from');

#    };

    return unless $object;

    my $doc = $self->new_ostatus_as;

    $doc->add_actor('...');
    $doc->add_verb('subscribe');
    $doc->add_object(type => 'person');

    # 'after_ostatus_follow' hook (Für evtl. pubsub_publish
};

sub unsubscribe {
    my $self = shift;
    my ($acct, $id);

    if ($_[0] =~ /^\d+$/) {
	$id = shift;
    } else {
	$acct = shift;
    };
};


1;
