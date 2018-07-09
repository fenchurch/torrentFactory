#!/bin/bash
if [[ "$EUID" != 0 ]]; then sudo -v; fi

scriptPID=$$
scriptPath="$(dirname "$0")"
scriptName="$(basename "$0")"

usage="$scriptName file or $scriptName torrentID torrentFile torrentPath"

mediaPath="/mnt/nas/Media"
tvPath="$mediaPath/TV Shows"
moviePath="$mediaPath/Movies"
log(){ 
    echo "[$(date +%F\ %T)] $(whoami) ($scriptPID) $scriptName - $@" >>/var/log/ingest.log
    echo "$@" >&2
    logger -i "$scriptName - $@"
}

if [ $# -eq 1 ]; then
    ingestMedia="$1"
elif [ $# -eq 3 ]; then
    ingestMedia="${3%/}/$2"
else
    log Missing Arguments.
    echo "Missing Arguments. Usage: $usage"
    exit 1;
fi
dependencies=(
    ffmpeg=/usr/bin/ffmpeg
    ffprobe=/usr/bin/ffprobe
    moveTV=~/bin/moveTV
)
translations=(
    translacion=Translation
)
mediaExtensions=( mp4 m4v mkv mov avi )
mediaExclusions=( '.*[Ss]ample.*' )

tvRegex='(^.+)\ \-\ S([0-9][0-9])E([0-9][0-9]).*$'

tag_tv(){ "$scriptPath/addTVTags.sh" "$@"; }
tag_movie(){ exit; }
#
#Short functions
#
checkDependencies() {
    #error counter
    local app appPath d missing=0
    #check dependencies
    for d in "${dependencies[@]}"; do
        app=${d%=*}
        appPath="${d##*=}"
        if [[ ! $(which $app) ]]; then
            if [[ ! -e $appPath ]]; then 
                eval "alias $app='$appPath'"
            else
                log "Missing $app from $(dirname $appPath)"
                (( missing++ ))
            fi
        fi
    done
    #exit if missing dependencies
    [[ $missing -gt 0 ]] && exit $missing || :
}
whitespace(){
    local r="$@"
    r="${r//[\.\_\(]/ }"
    r="${r//\ -\ / }"
    echo "${r%"${r##*[![:space:] ]}"}"
}
replace(){
    sed -i -e 's/$2/$3/g' <<< "$1"
}
lowercase() {
    tr '[:upper:]' '[:lower:]' <<<$@
}
translate() {
    local r="$@"
    for t in ${translations[@]}; do
        [[ "`lowercase $r`" == "`lowercase ${t%%=*}`" ]] && r=${t#*=} || :
    done
    echo "$r";
}
leading_zero() {
    #rewrite this for multiple digits
    local digits="$@"
    if [[ "${#digits}" == "1" ]]; then
        digits="0$digits"
    fi
    echo $digits
}
contains(){
    local stack needle="$1"
    shift
    for stack; do
        [[ "$needle" == "$stack" ]] && return || : ; done
    return 1
}
excludes(){
    local e match="$1"
    shift
    for e do [[ "$match" =~ $e ]] && return 1 || : ; done
}
find_media(){
    local f input="$@"
    if [[ -d "$input" ]]; then
        #check the directory if there there is a movie with the name of the directory
        for f in "$input/$(basename "$input")/"*.*; do
            if contains ${f##*.} ${mediaExtensions[@]} && excludes "$f" ${mediaExclusions[@]}; then
                echo $f
                return 0 
            fi
        done
        #check if there are any movies in the directory
        for f in "$input"/*; do
            if contains ${f##*.} ${mediaExtensions[@]} && excludes "$f" ${mediaExclusions[@]}; then
                echo $f
                return 0
            fi
        done
    fi
    #check if the input is the movie
    f=$(basename "$input")
    if [[ -e "$input" ]] && contains ${f##*.} ${mediaExtensions[@]}; then
        echo $input
        return 0 
    fi
    #return an error if no media exists
    log "find_media(): Could not find media:$input, Exiting"
    exit 1;
}
get_media_info(){
    local stream a v entries output=' -of default='
    while [ ${#@} -gt 1 ]; do
        case "$1" in
            --audio | -a) [[ "$2" =~ ^[0-9]+$ ]] && ( a="a:$2"; shift ) || a="a:0" ;;
            --video | -v) [[ "$2" =~ ^[0-9]+$ ]] && ( v="v:$2"; shift ) || v="v:0" ;;
            --entry | -e) entries="=$2"; shift ;;
        esac
        shift
    done
    file=$1     
    if [[ -n $a && -n $v ]]; then 
        stream='-show_streams'
    elif [[ -n $a || -n $v ]]; then 
        stream="-select_streams $a$v"
    fi
    if [[ -n $a || -n $v ]]; then
        output="${output}noprint_wrappers=1"
        if [[ -n $entries ]];then 
            output="$output:nokey=1"
        fi
    fi
    ffprobe -v error -hide_banner $stream -show_entries stream$entries$output $file
}
convert_media(){
    local a v ext filename="${@%.*}"
    ext="${@##*.}"
    v=h264
    a=aac
    mediaInfo="ffprobe -v error -hide_banner -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 -select_streams"
    if [[ $? == 1 ]]; then log "$@" atom not found; exit 1; fi
    [[ $($mediaInfo a:0 "$@") == $a ]] && a=copy || :
    [[ $($mediaInfo v:0 "$@") == $v ]] && v=copy || :
    if [[ $ext != mp4 || $a != copy || $v != copy ]]; then
        log Starting conversion of $@
        ffmpeg -y -i "$@" -c:v $v -c:a $a -strict -2 "$filename.mp4" 2>/tmp/error.log 
        [ $? -gt 0 ] && exit 4 || :
        log Completed conversion of $@
        echo "$filename.mp4"
        rm "$@"
        return
    fi
    log No conversion needed of $@
    echo "$@"
}
sort_media(){
    local name path ext output input="$@"
    name="$(basename "$input")"
    name="${name%.*}"
    ext="${input##*.}"

    tvRenameRegex='(^.+)[\-\_\.\ ]([sS\[]*([0-9]{1,2})[EeXx]([0-9]{2})).*$'
    movieRenameRegex='(^.*)([1-2]{1}[0-9]{3})[\)]*.*$'
    #Check if the filename is already formatted for TV
    if [[ "$name" =~ $tvRegex ]]; then
        echo "$input"
        return 0
    #Rename TV
    elif [[ "$name" =~ $tvRenameRegex ]]; then
        title="$( translate "$( whitespace ${BASH_REMATCH[1]} )" )"
        s="$( leading_zero "${BASH_REMATCH[3]}" )"
        e="$( leading_zero "${BASH_REMATCH[4]}" )"
        name="$title - S${s}E${e}"
        output="$(dirname "$input")/$name.$ext"
        mv -f "$input" "$output"
        log Renamed "$input" to "$output"
        echo "$output"
        return 0
    #Rename Movies
    elif [[ "$name" =~ $movieRenameRegex ]]; then
        title="$(whitespace "${BASH_REMATCH[1]}")"
        year="${BASH_REMATCH[2]}"
        name="${title} (${year})"
        output="$(dirname "$input")/$name.$ext"
        mv -f $input $output
        log Renamed "$input" to "$output"
        echo $output
        return 1
    fi

    echo $input
    return 2
}
move_tv(){
    storage="$1"
    file="$(basename "$2")"
    if [[ "$file" =~ (^.+)\ \-\ S([0-9][0-9])E([0-9][0-9]).*$ ]]; then
        path="$storage/${BASH_REMATCH[1]}/Season ${BASH_REMATCH[2]#0*}"
        if [ ! -d "$path" ]; then
            mkdir -p "$path"
            chmod 0777 "$path/.."
        fi
        chmod -R 0777 "$2"
        log "Moving $2 to $path"
        log $(cp -vf "$2" "$path" 2>&1 && rm "$2")
        [ $? -eq 0 ] && echo $path/$file || exit 1
    fi
}
main(){
    sudo -v
    inputFile="$@"
    log "Original File: $inputFile"
    mediaFile="$(find_media "$inputFile")"
    tempFile="/tmp/$(basename "$mediaFile")"
    log "main \"$mediaFile\""
    if [[ "$mediaFile" == "" ]]; then
        log "Non Media file: $inputFile"
        exit 1
    fi
    log "Moving to $tempFile"
    mv -f "$mediaFile" "$tempFile"
    mediaFile="$tempFile"
    #If the inputFile is a dir, remove it since we moved media to /tmp
    [[ -d "$inputFile" ]] && rm -r "$inputFile" || :

    mediaFile="$(convert_media "$mediaFile")"
    mediaFile="$(sort_media "$mediaFile")"
    mediaType=$?
    if [[ $mediaType == 0 ]]; then #its TV
        mediaFile="$(tag_tv "$mediaFile")"
        mediaFile="$(move_tv "$tvPath" "$mediaFile")"
        $scriptPath/plexScan.sh
        return
    fi
    if [[ $mediaType == 1 ]]; then
        log "tagging $mediaFile"
        tag_movie "$mediaFile";

        log "moving $mediaFile to $moviePath"
        mv "$mediaFile" "$moviePath"
        mediaFile="$moviePath/$(basename "$mediaFile")"
        return
    fi
    echo "$mediaFile"
}
#move_tv "$tvPath" "$1"
#Deluge exec will pass 1=TorrentID, 2=TorrentFile, 3=TorrentPath
echo "IngestMedia: $ingestMedia"
main "$ingestMedia"
