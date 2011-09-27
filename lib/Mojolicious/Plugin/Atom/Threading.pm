package Mojolicious::Plugin::Atom::Threading;
use Mojo::Base 'Mojolicious::Plugin::SerialXML';

our $PREFIX = 'thr';
our $NS = 'http://purl.org/syndication/thread/1.0';

sub new {  warn 'Only use as an extension to Atom.'; 1; };

# Add 'in-reply-to' element
sub add_in_reply_to {
  my ($self,
      $ref,
      $param) = @_;

  # No ref defined
  return unless defined $ref;

  # Adding a related link as advised in the spec
  if (defined $param->{href}) {
    $self->add_link($param->{href});
  };

  $param->{ref} = $ref;

  return $self->add_pref('in-reply-to' => $param );
};


# Add 'link' element for replies
sub add_replies_link {
  my ($self,
      $param) = @_;

  # No param defined
  return unless defined $param;

  if (exists $param->{count}) {
    $param->{$PREFIX . ':count'} = delete $param->{count};
  };

  if (exists $param->{updated}) {
    $param->{$PREFIX . ':updated'} = delete $param->{updated};
  };

  unless (exists $param->{type}) {
    $param->{type} = 'application/atom+xml';
  };

  # Needs atom as parent
  $self->add_link(rel => 'replies',  %$param );
};


# Add total value
sub add_total {
  my ($self,
      $count,
      $param) = @_;

  return unless $count;

  $param ||= {};

  return $self->add_pref('total' => $param => $count);
};

1;

__END__
