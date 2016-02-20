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
use Mojo::DOM;
use File::Spec;

use lib 'lib';
use Html;

use Data::Dumper;

my $config = plugin 'Config';

plugin 'TagHelpers';

my $file = Mojo::Asset::File->new( path => $config->{appSecrets} );
my $appSecrets = decode_json( $file->slurp )->{web};

$file = Mojo::Asset::File->new( path => File::Spec->catfile( $config->{searchDir}, $config->{search} ) );
my $search = $file->slurp;

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
    my $h = Html->new;

    $c->render( data => $h->html( 'The beginn..' ) );
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
        template        => 'list',
        action          => '',
        foundLocalFiles => $foundLocalFiles,
    );
};

sub checkLocalFiles {
    my $files = {};

    foreach my $dir( $config->{sourceFiles}, $config->{targetFiles} ) {
        opendir( my $dh, $dir ) or die "can't opendir $dir $!";

        while( my $file = readdir $dh ) {
            next unless -f File::Spec->catfile( $dir, $file );
            next unless $file =~ m/\.\w+$/;
            push @{$files->{$dir}}, $file;
        }

        closedir $dh;
    }

    return $files;
}

get '/check' => sub {
    my $c = shift;

    my $res;

    if( my $err = $c->param( 'error' ) ) {
        print Dumper $err;
    }
    elsif( my $data = $c->oauth2->get_token( 'google' => { scope => join ' ', @scopes } ) ) {
        $localStore->{accessTokenUrlPart} = "access_token=$data->{access_token}";

        my $url = 'https://www.googleapis.com/gmail/v1/users/me'.
                  "/messages?q=$search&".
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
    my $c    = shift;
    my $name = $c->stash( 'name' );

    my $sourcePath = File::Spec->catfile( $config->{sourceFiles}, $name );
    my $converter = qq(libreoffice --convert-to "html:XHTML Writer File:UTF8" --outdir $config->{targetFiles} '$sourcePath');
    system $converter;

    $name =~ s/doc/html/;
    my $targetPath = File::Spec->catfile( $config->{targetFiles}, $name );
    my $file = Mojo::Asset::File->new( path => encode( 'UTF-8', $targetPath ) );

    my $dom = Mojo::DOM->new( $file->slurp );

    say $dom->at( 'title' )->all_text;

    $c->render( inline => "Trying parse file: $name\n" );
};

app->start;
