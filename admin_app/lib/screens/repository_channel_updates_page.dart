import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/connected_channel_source.dart';
import 'channels_page.dart';

class RepositoryChannelUpdatesPage extends StatefulWidget {
  const RepositoryChannelUpdatesPage({super.key});
  @override
  State<RepositoryChannelUpdatesPage> createState()=>_RepositoryChannelUpdatesPageState();
}
class _RepositoryChannelUpdatesPageState extends State<RepositoryChannelUpdatesPage>{
  final source=ConnectedChannelSource(source:'repository-imports');
  late Future<Map<String,dynamic>> data=load();
  int page=0;bool working=false;
  Future<Map<String,dynamic>> load()=>source.request('updates',{'page':page});
  void refresh(){if(mounted)setState(()=>data=load());}
  String time(Object? value){final t=DateTime.tryParse(value?.toString()??'');return t==null?'Not checked':DateFormat('dd MMM, h:mm a').format(t.toLocal());}
  Future<void> sync()async{
    setState(()=>working=true);
    try{
      final result=await source.request('sync');refresh();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
        '${result['updated_lines']??0} updated • ${result['repaired']??0} published-key repairs • ${result['missing_or_ambiguous']??0} missing/ambiguous')));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Source check unavailable. Saved lines were kept.')));}
    finally{if(mounted)setState(()=>working=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Channel Source Updates'),actions:[
    IconButton(tooltip:'Check source updates',onPressed:working?null:sync,icon:const Icon(Icons.sync)),
  ]),body:FutureBuilder<Map<String,dynamic>>(future:data,builder:(context,snapshot){
    if(snapshot.hasError)return Center(child:TextButton(onPressed:refresh,child:const Text('Retry source updates')));
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final rows=(snapshot.data!['entries'] as List).whereType<Map>().toList();
    return Column(children:[
      const Padding(padding:EdgeInsets.all(12),child:Text('Imported channels are checked hourly. Only configurations verified against published media are updated.')),
      if(working)const LinearProgressIndicator(),
      Expanded(child:RefreshIndicator(onRefresh:()async{refresh();await data;},child:ListView.builder(itemCount:rows.length,itemBuilder:(_,i){
        final row=rows[i];final pending=row['configuration_pending']==true||row['configuration_status']=='requires_drm';
        final missing=row['source_missing']==true;
        return ListTile(title:Text(row['name']?.toString()??row['label']?.toString()??'Channel'),
          leading:Icon(missing?Icons.link_off:pending?Icons.pending_outlined:Icons.sync,color:missing||pending?Colors.orange:null),
          subtitle:Text('${row['repository']}\n${missing?'Source missing / ambiguous':pending?'Configuration pending':row['last_updated_at']!=null?'Updated ${time(row['last_updated_at'])}':'Checked ${time(row['last_source_check'])}'}'
            '${(row['changed_fields'] as List? ?? []).isEmpty?'':' • ${(row['changed_fields'] as List).join(', ')}'}'),
          isThreeLine:true,trailing:IconButton(tooltip:'Manage channel',icon:const Icon(Icons.edit_outlined),onPressed:()async{
            await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ChannelsPage(initialQuery:row['name']?.toString()??'')));refresh();
          }));
      }))),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        IconButton(onPressed:page>0?(){page--;refresh();}:null,icon:const Icon(Icons.chevron_left)),
        Text('${page*100+1}–${page*100+rows.length} / ${snapshot.data!['total']}'),
        IconButton(onPressed:(page+1)*100<(snapshot.data!['total'] as num)?(){page++;refresh();}:null,icon:const Icon(Icons.chevron_right)),
      ]),
    ]);
  }));
}
