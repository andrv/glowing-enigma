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
use Mojo::JSON qw( decode_json encode_json );
use Mojo::Util qw( spurt encode );
use MIME::Base64::URLSafe;
use File::Spec;

use Data::Dumper;

my $config = plugin 'Config';

plugin 'TagHelpers';

my $file = Mojo::Asset::File->new( path => $config->{appSecrets} );
my $appSecrets = decode_json( $file->slurp )->{web};

plugin 'OAuth2' => {
    google => {
        key    => $appSecrets->{client_id},
        secret => $appSecrets->{client_secret},
    }
};

my @scopes = qw(
    https://mail.google.com/
    https://www.googleapis.com/auth/gmail.modify
    https://www.googleapis.com/auth/gmail.readonly
);

my $localStore = {};

get '/' => sub {
    my $c = shift;
    $c->render( template => 'index' );
};

get '/showConfig' => sub {
    my $c = shift;

    $c->render(
        template   => 'showConfig',
        appSecrets => $appSecrets,
    );
};

get '/list' => sub {
    my $c = shift;
    my $foundLocalFiles = checkLocalFiles();

    $c->render(
        template        => 'work',
        action          => '',
        foundLocalFiles => $foundLocalFiles,
    );
};

get '/check' => sub {
    my $c = shift;

    my $res;

    if( my $err = $c->param( 'error' ) ) {
        print Dumper $err;
    }
    elsif( my $data = $c->oauth2->get_token( 'google' => { scope => join ' ', @scopes } ) ) {
        $localStore->{accessTokenUrlPart} = "access_token=$data->{access_token}";

        my $url = 'https://www.googleapis.com/gmail/v1/users/me'.
#                  '/messages?q=has:attachment is:unread&'.
                  '/messages?q=from:kueche@kabi-kamenz.de has:attachment is:unread&'.
                  $localStore->{accessTokenUrlPart};

        my $ua = Mojo::UserAgent->new;
        $res = $ua->get( $url )->res->json;

        my $messagesFound = $res->{resultSizeEstimate} ? 1 : 0;
        $c->stash( messagesFound => $messagesFound );

        my $messageData = [];

        foreach my $message( @{$res->{messages}} ) {
            my $metadata = { id => $message->{id} };

            $url = "https://www.googleapis.com/gmail/v1/users/me/messages/$message->{id}?$localStore->{accessTokenUrlPart}";
            my $res = $ua->get( $url )->res->json;

            foreach my $header( @{$res->{payload}->{headers}} ) {
                $metadata->{subj} = $header->{value} if $header->{name} eq 'Subject';
            }

            my $attachments = [];
            foreach my $messagePart( @{$res->{payload}->{parts}} ) {
                push(
                    @$attachments, {
                        filename => $messagePart->{filename},
                        id => $messagePart->{body}->{attachmentId},
                    }
                ) if $messagePart->{filename};
            }

            $metadata->{attachments} = $attachments;

            push @$messageData, $metadata;
        }
        $c->stash( messages => $messageData );
    }
    else {
        return;
    }

    $c->render(
        template => 'checking',
    );
};

get '/fetch/:message/:attachment/#name' => sub {
    my $c          = shift;
    my $message    = $c->stash( 'message' );
    my $attachment = $c->stash( 'attachment' );

    my $url = "https://www.googleapis.com/gmail/v1/users/me/messages/$message/attachments/$attachment?$localStore->{accessTokenUrlPart}";

    my $ua = Mojo::UserAgent->new;
    my $res = $ua->get( $url )->res->json;

    my $bytes = encode 'UTF-8', $res->{data};
    $bytes = urlsafe_b64decode $bytes;

    my $path = File::Spec->catfile( $config->{sourceFiles}, $c->stash( 'name' ) );

    spurt $bytes, $path;

    $c->redirect_to( '/list' );
};

get '/parse/#name' => sub {
    my $c = shift;

    $c->render( inline => 'Trying parse pdf file...' );
};

sub checkLocalFiles {
    my $files = [];
    my $dir   = $config->{sourceFiles};

    opendir( my $dh, $dir ) or die "can't opendir $dir $!";

    while( my $file = readdir $dh ) {
        next unless -f File::Spec->catfile( $dir, $file );
#        next unless $file =~ m/\.\w+$/;
        push @$files, $file;
    }

    closedir $dh;

    return $files;
}

app->start;
