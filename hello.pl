#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: hello-jerk.pl
#
#        USAGE: ./hello-jerk.pl  
#
#  DESCRIPTION: mojolicious start
#
#===============================================================================

use Mojolicious::Lite;
my $config = plugin 'Config';

plugin 'TagHelpers';

get '/' => sub {
    my $c = shift;
    $c->render(
        template => 'index',
        moreContent => "Hello sombody!\nBye.\n",
    );
};

get '/foo' => sub {
    my $c = shift;
    my $user = $c->param( 'user' ) || '';

    $c->render(
        template => 'index',
        moreContent => "Hello foo '$user' sombody!\nBye.\n",
    );
};

get '/bar' => sub {
    my $c = shift;
    $c->render(
        template => 'index',
        moreContent => "Hello bar sombody!\nBye.\n",
    );
};

get '/taghelpers' => sub {
    my $c = shift;

    $c->render(
        template => 'index',
        moreContent => 'Using tag helpers from Mojolicious',
    );
};

get '/showConfig' => sub {
    my $c = shift;

    $c->render( template => 'showConfig' );
};

app->start;
