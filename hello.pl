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
use Mojo::Util qw( spurt encode decode );
use Mojo::ByteStream;
use MIME::Base64::URLSafe;
use Mojo::DOM;
use File::Spec;

use lib 'lib';

use Data::Dumper;

my $config       = plugin 'Config';
my $sourceDir    = $config->{sourceDir};
my $convertedDir = $config->{converted};

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

    $c->render( template => 'index' );
};

get '/config' => sub {
    my $c = shift;

    my $out = $c->tag(
        ul => ( id => 'test' ) => sub { join "\n",
            $c->tag( li => '<a href="/">test</a>' ),
            $c->tag( li => sub { '<a href="/">test</a>' } ),
            $c->tag( li => sub { $c->link_to( test => '/' ) } ),
        }
    );

    $c->render( template => 'config', out => $out );
};

get '/list' => sub {
    my $c = shift;

    my $dirs;

    foreach my $dir( $sourceDir, $convertedDir ) {
        opendir( my $dh, $dir ) or die "can't opendir $dir $!";

        my $files;
        while( my $file = readdir $dh ) {
            next unless -f File::Spec->catfile($dir, $file);
            next unless $file =~ m/\.\w+$/;
            $files .= $c->tag(li => sub {$c->link_to(decode('UTF-8', $file) => "/convert/$file")}) if $dir eq $sourceDir;
            $files .= $c->tag(li => sub {$c->link_to(decode('UTF-8', $file) => "/parse/$file")}) if $dir eq $convertedDir;
        }

        $dirs .= $c->tag(ul => sub{
                $c->tag(li => sub{"$dir:". $c->tag(ul => sub{ $files})})
            }) if $files;

        closedir $dh;
    }

    $c->render(template => 'list', dirs => Mojo::ByteStream->new($dirs));
};

get '/check' => sub {
    my $c = shift;

    my $res;

    my $messageData = [];

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

        foreach my $message( @{$res->{messages}} ) {
            my $metadata = { id => $message->{id} };

            $url = "https://www.googleapis.com/gmail/v1/users/me/messages/$message->{id}?$localStore->{accessTokenUrlPart}";
            my $res = $ua->get( $url )->res->json;

            foreach my $header( @{$res->{payload}->{headers}} ) {
                $metadata->{subj} = $header->{value} if $header->{name} eq 'Subject';
            }

            my @attachments;
            foreach my $part(@{$res->{payload}{parts}}) {
                if( $part->{filename} ) {
                    my $fn = encode('UTF-8', $part->{filename});
                    my $attach = {filename => $part->{filename}};
                    $attach->{url} = "/fetch/$message->{id}/$part->{body}{attachmentId}/$fn" if $part->{filename} =~ m/jpg$|png$|doc$|pdf$/;

                    push @attachments, $attach;
                }
            }

            $metadata->{attachments} = [ @attachments ];

            push @$messageData, $metadata;
        }
    }
    else {
        return;
    }

    my $mails = @$messageData ? 'New mails:' : 'No new mails, try again later';
    foreach my $message ( @$messageData ) {
        my $at;
        foreach my $attach(@{$message->{attachments}}) {
            $at .= $c->tag(li => $attach->{url}
                ? sub{$c->link_to($attach->{filename} => $attach->{url})}
                : $attach->{filename}
            );
        }

        $mails .= $c->tag(ul => sub{
                $c->tag(li => sub{
                        $message->{subj}. $c->tag(ul => sub{$at})
                    })
            });
    }

    $c->render(template => 'check', mails => Mojo::ByteStream->new($mails));
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

    my $path = File::Spec->catfile( $sourceDir, $c->stash( 'name' ) );

    spurt $bytes, $path;

    $c->redirect_to( '/list' );
};

get '/convert/#name' => sub {
    my $c    = shift;
    my $name = $c->stash('name');

    my $sourcePath = File::Spec->catfile( $sourceDir, $name );
    my $converter = qq(libreoffice --convert-to "html:XHTML Writer File:UTF8" --outdir $convertedDir '$sourcePath');

    $c->render( inline => "Trying convert file: $name\n" );
    system $converter;

    $c->redirect_to( '/list' );
};

get '/parse/#name' => sub {
    my $c    = shift;
    my $name = $c->stash('name');

    my $targetPath = File::Spec->catfile( $convertedDir, $name );
    my $file = Mojo::Asset::File->new( path => encode( 'UTF-8', $targetPath ) );

    my $dom = Mojo::DOM->new( $file->slurp );

    say $dom->at( 'title' )->all_text;

    $c->redirect_to( '/list' );
};

app->start;
