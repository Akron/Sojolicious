# Sojolicious

Sojolicious is a toolkit for the federated social web, containing
plugins for the powerful web framework L<Mojolicious>
written in Perl.


# Synopsis

```perl
  use Mojolicious::Lite;

  # Load Plugins
  plugin 'Webfinger';
  plugin 'PubSubHubbub';
  plugin 'Salmon';

  # Esablish Salmon Endpoints:
  group {
    under '/salmon';
    (any '/:acct/mentioned')->salmon('mentioned');
    (any '/:acct/all-replies')->salmon('all-replies');
    (any '/signer')->salmon('signer');
  };

  # Add pubsubhubbub callback url
  (any '/pubsub')->pubsub;

  hook on_salmon_follow => sub {
    # ... You received a follow request
  };

  hook on_pubsub_content => sub {
    my ($c, $type, $dom) = @_;
    # ... You receive feed information you subscribed to
  };

  app->start;
```

# Goal

Sojolicious mainly focus on support for the
[OStatus](https://github.com/OStatus)
meta protocol and aims for a straight forward implementation of all
surrounding specifications.

Due to the success of Mastodon it is unlikely this path will be
followed in the future.

The design goal was to  make all plugins useful on their own,
as separated building blocks of OStatus, while playing well
with each other. All plugins are application (despite the fact
that they are Mojolicious plugins) and storage agnostic,
providing event driven hooks for usage.

See [nils-diewald.de](https://www.nils-diewald.de/development/sojolicious)
for recent updates.

# Plugins for ...

- [x] [ActivityStreams](http://activitystrea.ms/specs/atom/1.0/) via [XML::Loy::ActivityStreams](https://metacpan.org/pod/XML::Loy::ActivityStreams)
- [x] [Atom](https://www.ietf.org/rfc/rfc4287.txt) via [XML::Loy::Atom](https://metacpan.org/pod/XML::Loy::Atom)
- [x] [Atom-Threading-Extension](https://www.ietf.org/rfc/rfc4685.txt) via [XML::Loy::Atom::Threading](https://metacpan.org/pod/XML::Loy::Atom::Threading)
- [x] [HostMeta](http://tools.ietf.org/html/draft-hammer-hostmeta) via [Mojolicious-Plugin-HostMeta](https://metacpan.org/release/Mojolicious-Plugin-HostMeta)
- [x] [MagicSignatures](http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html) via [Crypt::MagicSignatures::Envelope](https://metacpan.org/release/Crypt-MagicSignatures-Envelope/) and [Crypt::MagicSignatures::Key](https://metacpan.org/release/Crypt-MagicSignatures-Key/)
- [ ] [OStatus](https://github.com/OStatus)
- [ ] [PortableContacts](http://portablecontacts.net/draft-spec.html)
- [x] [PubSubHubbub](https://github.com/pubsubhubbub) via [Mojolicious::Plugin::PubSubHubbub](https://metacpan.org/release/Mojolicious-Plugin-PubSubHubbub/)
- [ ] [Salmon](https://github.com/salmon-protocol)
- [x] [XRD](http://docs.oasis-open.org/xri/xrd/v1.0/xrd-1.0.html) via [Mojolicious::Plugin::XRD](https://metacpan.org/release/Mojolicious-Plugin-XRD)
- [x] [Webfinger](http://code.google.com/p/webfinger/wiki/WebFingerProtocol) via [Mojolicious::Plugin::WebFinger](https://metacpan.org/release/Mojolicious-Plugin-WebFinger)

There were plans to expand the scope to other social protocols later,
for example [OExchange](http://www.oexchange.org/spec/).

# Acknowledgement

- **ActivityStreams** was developed by Martin Atkins, Will Norris, Chris Messina, Monica Wilkinson, and Rob Dolin.
- **Atom** was developed by Mark Nottingham and Robert Sayre.
- **Atom** Threading Extensions> was developed by James M. Snell.
- **HostMeta** was developed by  Eran Hammer-Lahav and Blaine Cook.
- **MagicSignatures** was developed by John Panzer, Ben Laurie, and Dirk Balfanz.
- **Mojolicious** is written by Sebastian Riedel.
- **OStatus** was developed by Evan Prodromou, Brion Vibber, James Walker, and Zach Copley.
- **PortableContacts** was developed by Joseph Smarr.
- **PubSubHubbub** was developed by Brad Fitzpatrick, Brett Slatkin, and Martin Atkins.
- **Salmon** was developed by John Panzer.
- **Webfinger** was developed by Brad Fitzpatrick, Eran Hammer-Lahav, Blaine Cook, John Panzer, and Joe Gregorio.
- **XRD** was developed by Eran Hammer-Lahav and Will Norris.

... just to name the persons officially responsible for maintaining the code and the specifications.
Thanks to all contributors of these projects as well!

And thanks to all implementors of these specifications for inspiring code (which is referenced in the sourcecode).

Participation on conferences was supported by the BMBF-project [Linguistic Networks](http://project.linguistic-networks.net/).

# Where to learn more?

[http://mojolicio.us](http://mojolicio.us),[http://ostatus.org/](https://github.com/OStatus).

# ... and?

Copyright (C) 2011-2013, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.
