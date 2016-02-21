package Html;
#===============================================================================
#
#         FILE: Html.pm
#
#  DESCRIPTION: For html tags stuff
#
#===============================================================================

use strict;
use warnings;
 
sub new { bless {}, shift }

sub html {
    my $self    = shift;
    my $title   = shift || '';
    my $content = shift || '';

    return qq(<!DOCTYPE html>
<html>
  <head>
    <title>$title</title>
  </head>
  <body>
    $content
  </body>
</html>)
}

sub div {
    my $self    = shift;
    my $content = pop;
    my %attr    = @_;

    my $name = $attr{name} ? qq( name="$attr{name}") : '';

    return qq(<div$name>
      $content
    </div>)
}

sub ul {
    my $self    = shift;
    my $content = pop;
    my %attr    = @_;

    my $ul = join "</li>\n<li>", @$content;

    return qq(<ul>
      <li>$ul</li>
    </ul>)
}

sub link {
    my $self    = shift,
    my $content = pop,
    my %attr    = @_;

    my $href = $attr{to} ? qq( href="$attr{to}") : '';

    return "<a$href>$content</a>"
}

1;
