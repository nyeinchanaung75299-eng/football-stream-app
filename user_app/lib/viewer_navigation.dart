// Keep every Viewer entry point on the same bottom-navigation order.
const viewerSourceTabs = <String>['live', 'repository', 'soco', 'yyzb', 'cola', 'fawa', 'channels'];
int viewerSourceIndex(String source) => viewerSourceTabs.indexOf(source);
String viewerSourceAt(int index) => viewerSourceTabs[index];
