#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: hello.pl
#
#        USAGE: morbo hello.pl  
#
#  DESCRIPTION: mojolicious start
#
#===============================================================================

use Mojolicious::Lite;
use Mojo::Asset::File;
use Mojo::UserAgent;

my $config = plugin 'Config';

plugin 'TagHelpers';
plugin 'OAuth2';

get '/' => sub {
    my $c = shift;
    $c->render( template => 'index' );
};

get '/foo' => sub {
    my $c = shift;
    my $user = $c->param( 'user' ) || '';

    $c->render(
        template => 'index',
        moreContent => "Hello foo '$user' sombody!\nBye.\n",
    );
};

get '/showConfig' => sub {
    my $c = shift;

    my $file = Mojo::Asset::File->new( path => $config->{userNameFile} );
    my $gUserName = $file->slurp;
    
    $file = Mojo::Asset::File->new( path => $config->{devApiKey} );
    my $gApiKey = $file->slurp;

    $file = Mojo::Asset::File->new( path => $config->{appSecrets} );

    $c->render(
        template  => 'showConfig',
        gUserName => $gUserName,
        gApiKey   => $gApiKey,
    );
};

get '/work' => sub {
    my $c = shift;

    $c->render(
        template => 'work',
        action   => '',
    );
};

get '/work/:action' => sub {
    my $c = shift;
    my $action = $c->stash( 'action' );

    my $gJson;

    if( $action eq 'check' ) {
        #https://www.googleapis.com/gmail/v1/users/{userName}%40gmail.com/messages?q=from%3Akueche%40kabi-kamenz.de+has%3Aattachment+is%3Aunread&key={YOUR_API_KEY}
        my $file = Mojo::Asset::File->new( path => $config->{userNameFile} );
        my $gUserName = $file->slurp;
        
        $file = Mojo::Asset::File->new( path => $config->{devApiKey} );
        my $gApiKey = $file->slurp;

        my $url = 'https://www.googleapis.com/gmail/v1/users/'.
                  $gUserName.
                  '@gmail.com/messages?q=from:kueche@kabi-kamenz.de has:attachment is:unread&key='.
                  $gApiKey;

        my $ua = Mojo::UserAgent->new;
        $gJson = $ua->get( $url )->res->json;
    }

    $c->render(
        template => 'workaction',
        action   => $action,
        gJson    => $gJson,
    );
};

app->start;
