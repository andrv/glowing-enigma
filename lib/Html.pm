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
    <dif name="nav">
      <ul>
        <li><a href="/">Home</a></li>
        <li><a href="/list">Working on the file</a></li>
        <li><a href="/showConfig">Show configuration</a></li>
      </ul>
    </div>
    $content
  </body>
</html>)
}

1;
