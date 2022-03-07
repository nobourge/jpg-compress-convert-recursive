#!/bin/bash

# november 2021
# Noe Bourgeois

shopt -s extglob

# Parameters for convert
READ_PARAMETERS='-auto-orient -colorspace RGB' 
WRITE_PARAMETERS='-quality 85% -colorspace sRGB -interlace Plane -define jpeg:dct-method=float -sampling-factor 4:2:0'
SMALLEST_SIDE='^'
CHEVRON='>'
# Supported asked_extension
declare -a SUPPORTED_EXTENSIONS=("jpg" 
                              "jpeg" 
                              "jpe" 
                              "jif" 
                              "jfif" 
                              "jfi" 
                              "JPG" 
                              "JPEG" 
                              "JPE" 
                              "JIF" 
                              "JFIF" 
                              "JFI" )
# Return values
BAD_USAGE=1
CONVERT_ERR=2
NO_EXIST=3
NOT_JPEG=4

ERROR=''

# Formatted usage messages
SHORT_USAGE="\e[1mUSAGE\e[0m
    \e[1m${0}\e[0m [\e[1m-c\e[0m] [\e[1m-r\e[0m] [\e[1m-e\e[0m \e[4mextension\e[0m] \e[4mresolution\e[0m [\e[4mfilename_or_directory\e[0m]
or
    \e[1m${0} --help\e[0m
for detailed help."
USAGE="$SHORT_USAGE

The order of the options does not matter. However, if \e[4mfilename_or_directory\e[0m is given and is a number, it must appear after \e[4mresolution\e[0m.

  \e[1m-c\e[0m, \e[1m--strip\e[0m
    Compress more by removing metadata from the file.

  \e[1m-r\e[0m, \e[1m--recursive\e[0m
    If \e[4mfilename_or_directory\e[0m is a folder, recursively compress JPEG in subdirectories.
    Has no effect if \e[4mfilename_or_directory\e[0m is a regular file.
    This option has the same effect when file and directories are given on stdin.

  \e[1m-e\e[0m \e[4mextension\e[0m, \e[1m--ext\e[0m \e[4mextension\e[0m
    Change the asked_extension of processed files to \e[4mextension\e[0m, even if the compression fails or does not actually happen.
    Renaming does not take place if it gives a filename that already exists, nor if the file being processed is not a JPEG file.

  \e[4mresolution\e[0m
    A number indicating the size in pixels of the smallest side.
    Smaller images will not be enlarged, but they will still be potentially compressed.

  \e[4mfilename_or_directory\e[0m
    If a filename is given, the file is compressed. If a folder is given, all the JPEG files in it are compressed.
    Can't begins with a dash (-).
    If it is not given at all, ${0} process files and directories whose name are given on stdin, one by line.

\e[1mDESCRIPTION\e[0m
    Compress the given picture or the jpeg located in the given folder. If none is given, read filenames from stdin, one by line.

\e[1mCOMPRESSION\e[0m
    The file written is a JPEG with quality of 85% and chroma halved. This is a lossy compression to reduce file size. 
    However, it is calculated with precision (so it is not suitable for creating thumbnail collections of large images). 
    The steps of the compression are:

      1. The entire file is read in.
      2. Its color space is converted to a linear space (RGB). This avoids a color shift usually seen when resizing images.
      3. If the smallest side of the image is larger than the given asked_resolution (in pixels), the image is resized so that this side has this size.
      4. The image is converted (back) to the standard sRGB color space.
      5. The image is converted to the frequency domain according to the JPEG algorithm using an accurate Discrete Cosine Transform (DCT is calculated with the float method) 
      and encoded in JPEG 85% quality, chroma halved. (The JPEG produced is progressive: the loading is done on the whole image by improving the quality gradually)."

function print_without_formatting () {
    # supprime le formatage par exemple, si la sortie ne se fait pas sur une console mais
    # est redirigée vers un fichier

    # Output the value of "$1" without formatting
    echo "$1" | sed 's/\\e\[[0-9;]\+m//g'
}

function check_for_help (){
  # -h, --help, help
  # Si une de ces options est donnée, 
    for param ; do
        # command || command exécute la deuxième command seulement si la première retourne non-zéro.
        # La valeur de retour est la valeur de retour de la dernière commande exécutée
        if [ $param = '-h' ] || [ $param = '--help' ] || [ $param = 'help' ] 
          then
            # les autres options sont ignorées, 
            # un message d’aide détaillé est aﬀiché sur la stdout
            # 1>&2 est la façon usuelle de rediriger le stdout (1) vers le stderr (2)
            echo -e "$USAGE" 1>&2
            # le script quitte avec succès.
            exit
        fi
    done
    # echo "no help asked"
}

function parse_args () {
    check_for_help "$@"
    additional_write_parameters=''
    files_or_folders=()
    asked_extension=''
    recursive=false
    asked_resolution=''
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -c|--strip)
                additional_write_parameters=' -strip'
                # echo "additional write parameters: ' -strip'"
                shift
                ;;
            -r|--recursive)
                # Si un dossier est donné en entrée, compress_jpg.sh travaille aussi dans les sous-dossiers
                # récursivement
                recursive=true
                # echo "recursive: true"
                shift
                ;;
            -e|--ext)
                # Pour chaque fichier JPEG sélectionné pour la compression : 
                # compress_jpg.sh change l’extension du fichier en l’extension donnée, 
                # ou ajoute l’extension si le fichier n’en a pas. 
                if [ $# -lt 2 ] ; then
                    echo '-e|--ext requires an argument' 1>&2
                    exit $BAD_USAGE
                fi
                asked_extension_supported=false
                i=0
                #le script vérifie que l’extension donnée est une de 
                #jpg, jpeg, jpe, jif, jfif, jfi, JPG, JPEG,JPE, JIF, JFIF, JFI.
                while ! $asked_extension_supported && [ $i -lt ${#SUPPORTED_EXTENSIONS[@]} ]
                    do 
                        supported_extension=${SUPPORTED_EXTENSIONS[$i]};
                        # echo "$supported_extension"

                        if [ "$2" == "$supported_extension" ]
                            then asked_extension_supported=true
                            # echo "asked extension supported"
                        fi
                        i=$[$i+1]
                done

                if $asked_extension_supported
                  then 
                    asked_extension="$2"
                    # echo "asked extension: "$2""
                else
                  # un message d’erreur est aﬀiché sur stderr
                  echo "-e argument must be one of jpg, jpeg, jpe, jif, jfif, jfi 
                  (or uppercase version of one)" 
                  echo -e "$SHORT_USAGE"
                  # le script quitte avec erreur.
                  exit $BAD_USAGE
                fi
                shift ; shift
                ;;

            +([[:digit:]]) )
                # La taille (en pixels) demandée pour le plus petit côté de l’image, 
                # si celui-ci est plus grand dans le fichier d’origine. 
                # Ce paramètre est un entier positif (chaîne de caractère qui ne
                # correspond pas au pattern “''|*[!0-9]*” utilisable dans un case bash)
                if [[ -z "$asked_resolution" ]]
                  then
                    asked_resolution="$1"
                    # echo "asked_resolution: $1"

                elif [ ! ${#files_or_folders[*]} ]
                    then
                      files_or_folders+=("$1")
                else
                  echo "only asked_resolution and file name can be a digit"
                  exit $BAD_USAGE
                fi
                shift
                ;;

            -*)
                # Pour éviter des erreurs, 
                # le script doit refuser les entrées commençants par un tiret (“-”). 
                echo "Option inconnue: $1"

                #Si l’utilisateur veut donner une entrée commençant par un tiret, 
                #il peut utiliser le stdin:
                echo "to enter a file or folder name beginning with (“-”),
                 please use the stdin like so:
                 -my-file.jpg | ./compress_jpg.sh 1600"

                exit $BAD_USAGE
                ;;

            *)
                if [ ${#files_or_folders[@]} -eq 0 ]
                    then
                      # files_or_folders
                      # Spécifie une entrée.
                      files_or_folders+=("$1")
                      shift
                else
                    # un seul nom de fichier ou dossier peut être donné en argument
                    echo "$1 is unexpected"
                    exit $BAD_USAGE
                fi
                ;;
        esac
    done

    # Tous les paramètres sont facultatifs, sauf la résolution. 
    if [ -z "$asked_resolution" ]
      then
        echo "Missing resolution"
        echo -e "$SHORT_USAGE"
        exit $BAD_USAGE
    fi
    
    if [ ${#files_or_folders[@]} -eq 0 ]
      # cette option n’est pas donnée, 
      then
        echo "
        no file or folder given as argument,
        please enter at least 1 then press [CTRL]+[D]"
        # le script lit son stdin en traitant chaque ligne comme une entrée.
        while read arg
          do
            if [ ! -z "${arg}" ]
              then
                files_or_folders+=("$arg")
            fi
        done
    fi

    if [ ! ${#files_or_folders[@]} -gt 0 ]
      then
        echo "
        0 file or folder given"
        echo -e "$USAGE"
        exit $BAD_USAGE
    fi
    # echo "parsing done"
}

function is_jpeg () {
    # un fichier est un JPEG si la sortie de file -i nom_de_fichier contient image/jpeg
    info=$(file --mime-type "$1")
    #echo "$info"
    format=${info: -10}
    if  [ $format = "image/jpeg" ]  
      then return 0
    fi
    return 1
}

function display_dimensions () {
  width=$(identify -format '%w' "${1}")
  echo "width: $width"

  height=$(identify -format '%h' "${1}")
  echo "height: $height"

  #smallest_side=$(( width < height ? width : height ))
  #echo "smallest side: $smallest_side"
}

function normalize () {
    echo "
    normalizing ${1}
    "
    #Si l’utilisateur le demande avec l’option -e,
    #l’extension des fichiers JPEG sélectionnés pour la compression est normalisée
    if is_jpeg "${1}"
      then 
        #le fichier sélectionné est un fichier JPEG  
        #echo  "${1} format is jpeg"
        if [ -n "$asked_extension" ]
          then
            #le parametre asked_extension n'est pas vide 
            asked_file_name="$filename.$asked_extension"        
            #echo "asked_file_name: $asked_file_name"     

            path="$dirname/$asked_file_name"  
            #echo "new path: $path"
            if [ -e "$path" ]
              #le nom de fichier produit existe déjà pour un autre fichier
              then
                #Ce renommage n’a pas lieu
                echo "$path already exists,
                $1 not renamed
                "
            else
              mv "$1" "$path"
              echo " $basename renamed to $asked_file_name"
              file="$path"
            fi    
        fi 
    else
      echo "
      'compress jpg' compresses jpeg files,
      $1 is not of type jpeg,
      $1 not renamed, not compressed
      "
      ERROR=$NOT_JPEG
      return $NOT_JPEG

    fi
}

function compress(){
  
  #Si output_filename a l’extension d’un autre type d’image, le fichier produit par cette com-
  #mande est une image d’un type correspondant à son asked_extension. ImageMagick va prendre en compte
  #toutes les options données que le format demandé supporte.
  if [ -z $asked_extension ]
    then
      point_extension=".$extension"
      #echo "$point_extension"
      TEMP="$(mktemp ./tmp.XXXXXX$point_extension)" 
  else
      TEMP="$(mktemp ./tmp.XXXXXX.$asked_extension)" 
  fi
  # un fichier temporaire
  #echo "
  #               bytes
  #  original:   $(stat -c%s "${path}") 
  #  empty TEMP: $(stat -c%s "$TEMP")"
  #tmp = mktemp 2> /dev/null || mktemp -t compress_jpg

  #ImageMagick's convert écrit une version compressée de l’image dans tmp

  if convert ${READ_PARAMETERS} "${path}" -resize "${asked_resolution}"x"${asked_resolution}"${SMALLEST_SIDE}${CHEVRON}${additional_write_parameters} ${WRITE_PARAMETERS} "${TEMP}"
  
    then
      echo "
                  bytes
      original :  $(stat -c%s "${path}") 
      compressed: $(stat -c%s "$TEMP")
      "

      if [ $(stat -c%s "$TEMP") -lt $(stat -c%s "${path}") ]
        #le temporaire obtenu est plus léger que l’image d’origine
        then
          #il est utilisé pour remplacer le fichier d’origine
          cp "${TEMP}" "${path}" 
          echo "
          "${1}" compressed 
          "
          display_dimensions "${1}"
      else  
        echo "Not compressed. File left untouched. (normal)
        "
      fi
  
  else
    echo "Error while compressing "${1}". File left untouched
    "
    rm "$TEMP"
    exit $CONVERT_ERR
  fi
  rm "$TEMP"
}

function explore(){
  file=${1}
  if [ -d "$file" ]
    then
      #files_or_folders existe et est un répertoire
      if $recursive || [ ${2} -lt 1 ]
        #travaille sur tous les JPEG (détectés comme tels par file) du dossier et, 
        #si -r est spécifié, des sous-dossiers récursivement.
        then
          # echo "exploring "$file""  
          cd $file
          for subfile in *
            do
              #echo " current: $subfile"
              # echo "depth: ${2}"
              explore "$subfile" $(( ${2} + 1 )) "$3"
          done
          cd ..
      fi

  elif [ -f "$file" ]
      then
        #files_or_folders existe et est un fichier
        dirname="$(dirname "$file")"
        # echo "dirname: $dirname"

        basename="$(basename "$file")"
        # echo "basename: $basename"

        path="$dirname/$basename"
        # echo "path: $path"

        filename="${basename%.*}"
        # echo "filename: $filename"

        extension="${basename##*.}"
        # echo "extension: $extension"

        if normalize "$file"
          then
            display_dimensions "$file"

            #echo "compressing $file"
            compress "$file" "$asked_resolution" "$additional_write_parameters"
        fi
        
  else
      # cette option est donnée mais n’existe pas, 
      # le script aﬀiche un message d’erreur sur stderr et quitte avec une erreur (3)
      echo "$file does not exist"
      ERROR=$NO_EXIST
  fi
}


parse_args "$@"

echo "

Welcome to compress_jpg

${#files_or_folders[@]} file(s) or folder(s) to compress and/or explore:"
for file in "${files_or_folders[@]}"
  do echo " $file"
done

echo "
asked_resolution: $asked_resolution "

if $recursive
  then echo "recursive: $recursive "
fi

if [ -n $additional_write_parameters]
  then echo "additional_write_parameters: $additional_write_parameters"
fi


depth=0

for file in "${files_or_folders[@]}"
  do explore "$file" "$depth" "$asked_resolution"
done

if [ -n $ERROR ]
  then exit $ERROR
fi

    
 
