import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const dest=new URL('../downloads/nuget/',import.meta.url);
await mkdir(dest,{recursive:true});
const version='9.0.22';
for(const id of ['microsoft.netcore.app.runtime.win-x64','microsoft.windowsdesktop.app.runtime.win-x64','microsoft.aspnetcore.app.runtime.win-x64']){
  const name=`${id}.${version}.nupkg`,file=new URL(name,dest);
  let bytes;
  try{bytes=await readFile(file);}catch{
    const response=await fetch(`https://api.nuget.org/v3-flatcontainer/${id}/${version}/${name}`);
    if(!response.ok)throw Error(`${id}: ${response.status}`);
    bytes=Buffer.from(await response.arrayBuffer());await writeFile(file,bytes);
  }
  // NuGet verifies the Microsoft package signatures during restore; retain a local integrity manifest as well.
  await writeFile(new URL(name+'.sha256',dest),createHash('sha256').update(bytes).digest('hex')+'\n');
  console.log(`Runtime package ready: ${id} ${version}`);
}
