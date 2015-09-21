#Realtime Messaging SDK for React-Native

[Realtime Cloud Messaging](http://framework.realtime.co/messaging) is a highly-scalable pub/sub message broker, allowing you to broadcast messages to millions of users, reliably and securely. It's all in the cloud so you don't need to manage servers.

[React Native](http://facebook.github.io/react-native/) enables you to build world-class application experiences on native platforms using a consistent developer experience based on JavaScript and React.


More information can be found on the
[Realtime native iOS SDK reference documentation](http://messaging-public.realtime.co/documentation/ios/2.1.0/index.html).


##Installation

* Create a new react-native project. [Check react-native getting started](http://facebook.github.io/react-native/docs/getting-started.html#content)

* On the terminal, go to PROJECT_DIR/node_modules/react-native.

* Execute

		 npm install --save react-native-realtimemessaging-ios

* Drag RCTRealtimeMessaging.xcodeproj from the node_modules/react-native-	realtimemessaging-ios folder into your XCode project. Click on the project 	in XCode, goto Build Phases then Link Binary With Libraries and add 	libRCTRealtimeMessaging.a

* Drag RCTRealtimeMessaging.js to the root of your project.

 You are ready to go.

---



##ReatimeMessagingIOS class reference

###Import ReatimeMessaging to your project

	var module = require('RCTRealtimeMessagingIOS');
	var RCTRealtimeMessaging = new module();

###Event handling

In order to get event notifications from the native SDK, the JavaScript interface has two methods for adding and removing event registration.

**RTEventListener(notification, callBack: Function)** <br>

RTEventListener registers a given event name on the ***notification*** field and a given ***callback function*** to be fired when the event occurs. 

***Example:***

	var module = require('RCTRealtimeMessagingIOS');
	var RCTRealtimeMessaging = new module();	
	
	RCTRealtimeMessaging.RTEventListener("onConnected",this._onConnected),

**RTRemoveEventListener(notification)**

RTRemoveEventListener removes an event registration. After this method when the event occurs the ***callback*** will not be fired.

***Example:***

	var module = require('RCTRealtimeMessagingIOS');
	var RCTRealtimeMessaging = new module();	
	
	RCTRealtimeMessaging.RTEventListener("onConnected",this._onConnected),
	RCTRealtimeMessaging.RTRemoveEventListener("onConnected"),

  

***Complete event list:***

* onConnected - Occurs when the client connects

* onDisconnect - Occurs when the client disconnects

* onReconnect - Occurs when the client reconnects

* onReconnecting - Occurs when the client is attempting to reconnect

* onSubscribed - Occurs when the client has successfully subscribed a channel. The event notification data is `{"channel":channel}`

* onUnSubscribed - Occurs when the client has successfully unsubscribed a channel. The event notification data is `{"channel":channel}`

* onException - Occurs when there is an exception. The event notification data is `{"error":error.localizedDescription}`

* onMessage - Occurs when a message is received. The event notification data is `{"message": message,"channel": channel}`

* onPresence - Gets the subscriptions in the specified channel and if active the first 100 unique connection metadata:
	- On success -> `{"result": result}` 
	- On error -> `{"error": error}` 

* onEnablePresence - Enables presence for the specified channel with the first 100 unique connection metadata:
	- On success -> `{"result": result}`
	- On error -> `{"error": error}`
		 
* onDisablePresence - Disables presence for the specified channel:
	- On success -> `{"result": result}` 
	- On error -> `{"error": error}` 
	
###Push notification handling ( available from 1.0.6 )

####Configure your project for push notifications handling

To configure your react-native project to receive push notifications you must follow [this guide](http://messaging-public.realtime.co/documentation/starting-guide/mobilePushAPNS.html) for the iOS platform.
After this process you must drag AppDelegate+RealtimeRCTPushNotifications(.m, .h) category from RCTRealtimeMessaging plugin folder to your project, where AppDelegate class is, and you are ready to go.

####Handling automatic push notifications through javascript

To receive push notifications in a RealtimeMessaging channel you must use the SubscribeWithNotifications method. The onMessage event listener will be the only entry point for automatic push notifications(sent using a Realtime client send method), so when the application starts you must connect and subscribe the channels for handling that type of notifications.

***Example:***

	RCTRealtimeMessaging.RTSubscribeWithNotifications(this.state.channel, true);
	RCTRealtimeMessaging.RTEventListener("onMessage",this._onMessage),
	_onMessage: function(messageEvent)
	{ 
		this._log("Received message or automatic notification: ["+messageEvent.message+"] on channel ["+ messageEvent.channel+"]");  
	},

####Handling custom push notifications through javascript

For handling custom push notifications ( sent using the Realtime mobile push notifications REST API) we added the following event listener:

* RTCustomPushNotificationListener(callBack: Function)

***Example:***

	componentDidMount: function(){
  		RCTRealtimeMessaging.RTCustomPushNotificationListener(this._onNotification);
	},
	
	_onNotification: function(data)
	{ 
	  this._log("Received notification: " + JSON.stringify(data));  
	},

----------

###Methods

#####RTConnect(config)

Connects the client to Realtime server with the given configuration.

**Parameters**

* appkey - Realtime application key
* token - Authentication token
* connectionMetadata - Connection metadata string
* clusterUrl or url - The Realtime Messaging cluster or server URL

***Example:***

	RCTRealtimeMessaging.RTEventListener("onConnected",function(){
		console.log('Connected to Realtime Messaging');
	}),	
	
	RCTRealtimeMessaging.RTConnect(
    {
      appKey:this.state.appKey,
      token:this.state.token,
      connectionMetadata:this.state.connectionMetadata,
      clusterUrl:this.state.clusterUrl
    });


----------

#####RTDisconnect()

Disconnects the client from the Realtime server.

***Example:***

	RCTRealtimeMessaging.RTEventListener("onDisconnect", function(){
		console.log('Disconnected from Realtime Messaging');
	}),
	
	RCTRealtimeMessaging.RTDisconnect();

----------
	    
#####RTSubscribe(channel, subscribeOnReconnect: boolean)

Subscribes a pub/sub channel to receive messages.

**Parameters**

* channel - Channel name

* subscribeOnReconnected -
Indicates whether the client should subscribe the channel when reconnected (if it was previously subscribed when connected).

***Example:***

	RCTRealtimeMessaging.RTEventListener("onSubscribed", function(subscribedEvent){
		console.log('Subscribed channel: ' + subscribedEvent.channel);
	}),
	
	RCTRealtimeMessaging.RTSubscribe("MyChannel", true);

----------

#####RTSubscribeWithNotifications(channel, subscribeOnReconnect: boolean)

Subscribes a pub/sub channel with Push Notifications Service, to receive messages even if the app is not in foreground.

**Parameters**

* channel - Channel name

* subscribeOnReconnected -
Indicates whether the client should subscribe to the channel when reconnected (if it was previously subscribed when connected).

***Example:***

	RCTRealtimeMessaging.RTSubscribeWithNotifications("MyChannel", true);

----------

#####RTUnsubscribe(channel)

Unsubscribes a channel.

**Parameters**

* channel - Channel name.

***Example:***

	RCTRealtimeMessaging.RTUnsubscribe("MyChannel");

----------

#####RTSendMessage(message, channel)

Sends a message to a pub/sub channel.

**Parameters**

* channel - Channel name

* message - The message to send (a string/stringified JSON object)

***Example:***

	RCTRealtimeMessaging.RTSendMessage("Hello World","MyChannel");

----------

#####RTEnablePresence(aUrl, aIsCluster:boolean, aApplicationKey, aPrivateKey, channel, aMetadata)

Enables presence for the specified channel with first 100 unique connection metadata.

**Parameters**

* channel - Channel to enable presence

* applicationKey - Realtime application key

* isCluster - Specifies if url is a Realtime cluster

* metadata - Collect the first 100 unique connection metadata of subscribers

* privateKey - The Realtime application private key

* url - Realtime server or cluster URL

***Example:***

	RCTRealtimeMessaging.RTEventListener("onEnablePresence", function(event){
		if(event.result){
			console.log('Realtime enablePresence result: ' + event.result);
		}else{
			console.log('Realtime enablePresence error: ' + event.error);
		}
	}),
	
	RCTRealtimeMessaging.RTEnablePresence(aUrl, aIsCluster, aApplicationKey, aPrivateKey, channel, aMetadata);
	

----------

#####RTDisablePresence(aUrl, aIsCluster:boolean, aApplicationKey, aPrivateKey, channel, aMetadata)

Disables presence for the specified channel.

**Parameters**

* channel - Channel to disable presence

* applicationKey - Realtime application key

* url - Realtime server or cluster URL

* isCluster - Specifies if url is a Realtime cluster
* 
* privateKey - The Realtime application private key

***Example:***
	
	RCTRealtimeMessaging.RTEventListener("onDisablePresence", function(event){
		if(event.result){
			console.log('Realtime disablePresence result: ' + event.result);
		}else{
			console.log('Realtime disablePresence error: ' + event.error);
		}
	}),
	
	RCTRealtimeMessaging.RTDisablePresence(aUrl, aIsCluster, aApplicationKey, aPrivateKey, channel, aMetadata);

----------

#####RTPresence(aUrl, aIsCluster:boolean, aApplicationKey, aAuthenticationToken, channel)

Gets a dictionary with the total number of subscriptions in the specified channel and if active the first 100 unique connection metadata of the subscribers.

**Parameters**

* channel - Channel with presence data active

* applicationKey - Realtime application key

* url - Realtime server or cluster URL

* isCluster - Specifies if url is a Realtime cluster

* authenticationToken - Authentication token with permissions to the presence service

***Example:***

	RCTRealtimeMessaging.RTEventListener("onPresence", function(event){
		if(event.result){
			console.log('Realtime presence result: ' + JSON.stringify(event.result));
		}else{
			console.log('Realtime presence error: ' + event.error);
		}
	}),
	
	RCTRealtimeMessaging.RTPresence(aUrl, aIsCluster, aApplicationKey, aAuthenticationToken, channel);

----------

#####RTIsSubscribed(channel, callBack: function)

Indicates whether a given channel is currently subscribed.

**Parameters**

* channel - Channel name.

* callback - Callback function to be called with the result (true or false).

***Example:***

	RCTRealtimeMessaging.RTIsSubscribed("MyChannel", function(result){
		if(result == true){
			console.log('channel is subscribed');
		}else{
			console.log('channel is not subscribed');
		}
	});

----------

#####RTSaveAuthentication(url, isCluster, authenticationToken, authenticationTokenIsPrivate, applicationKey, timeToLive, privateKey, permissions, callBack: function)

Authenticates a token with the given channel permissions.

**Parameters**

* url - Realtime server or cluster URL

* isCluster - Specifies if url is a Realtime cluster

* authenticationToken - The token to authenticate 

* authenticationTokenIsPrivate -
Indicates whether the authentication token is private (1) or not (0). Private tokens can only be used by one client

* applicationKey -
Realtime application key

* timeToLive -
The allowed inactivity time (in seconds) for the authenticated token

* privateKey - The Realtime application private key

* permissions -
The channels and their permissions (w: write, r: read, p: presence)

* callback -
Callback function with the result (true or false).

***Example:***

	RCTRealtimeMessaging.RTSaveAuthentication(url, isCluster, authenticationToken, authenticationTokenIsPrivate, applicationKey, timeToLive, privateKey, permissions, function(result){
	
		if(result == true){
			console.log('Authentication saved successfully');
		}else{
			console.log('Error saving authentication');
		}
	});

----------

#####RTGetHeartbeatTime(callBack: function)

Get the client heartbeat interval.

**Parameters**

* callback -
Callback function with the heartbeat interval value

***Example:***
	
	RCTRealtimeMessaging.RTGetHeartbeatTime(function(result){
		console.log('HeartbeatTime for this client is: ' + result);
	});

----------

#####RTSetHeartbeatTime(newHeartbeatTime)

Sets the client heartbeat interval.

**Parameters**

* newHeartbeatTime - The new heartbeat interval

***Example:***
	
	RCTRealtimeMessaging.RTSetHeartbeatTime(10);

----------

#####RTGetHeartbeatFails(callBack: function)

Number of times the heartbeat can fail before the connection is reconnected

**Parameters**

* callBack - The callback function to get the HeartbeatFails value

***Example:***
	
	RCTRealtimeMessaging.RTGetHeartbeatFails(function(result){
		console.log('HeartbeatFails Time for this client is: ' + result);
	});

----------

#####RTSetHeartbeatFails(newHeartbeatFails)

Sets the number of times the heartbeat can fail before the connection is reconnected

**Parameters**

* newHeartbeatFails - The new heartbeat fails value

***Example:***
	
	RCTRealtimeMessaging.RTSetHeartbeatFails(3);

----------

#####RTIsHeartbeatActive(callBack: function)

Indicates whether the client heartbeat is active or not.

**Parameters**

* callBack - The callback function with the result

***Example:***
	
	RCTRealtimeMessaging.RTIsHeartbeatActive(function(result){
		if(result == true){
			console.log('heartbeat active');
		}else{
			console.log('heartbeat inactive');
		}		
	});

----------

#####RTEnableHeartbeat()

Enables the client heartbeat.

***Example:***
	
	RCTRealtimeMessaging.RTEnableHeartbeat()

----------

#####RTDisableHeartbeat()

Disables the client heartbeat.

***Example:***
	
	RCTRealtimeMessaging.RTDisableHeartbeat()



## Full example ( index.ios.js )

	'use strict';
	
	var React = require('react-native');
	var module = require('RCTRealtimeMessagingIOS');
	var RCTRealtimeMessaging = new module();
	
	var messages = [];
	
	var {
	  AppRegistry,
	  Image,
	  StyleSheet,
	  Text,
	  Navigator,
	  TextInput,
	  ScrollView,
	  TouchableHighlight,
	  ListView,
	  View
	} = React;
	
	
	var RealtimeRCT = React.createClass({ 
	
	  doConnect: function(){
	    this._log('Trying to connect!');
	
	    RCTRealtimeMessaging.RTEventListener("onConnected",this._onConnected),
	    RCTRealtimeMessaging.RTEventListener("onDisconnected",this._onDisconnected),
	    RCTRealtimeMessaging.RTEventListener("onSubscribed",this._onSubscribed),
	    RCTRealtimeMessaging.RTEventListener("onUnSubscribed",this._onUnSubscribed),
	    RCTRealtimeMessaging.RTEventListener("onException",this._onException),
	    RCTRealtimeMessaging.RTEventListener("onMessage",this._onMessage),
	    RCTRealtimeMessaging.RTEventListener("onPresence",this._onPresence);
	
	    RCTRealtimeMessaging.RTConnect(
	    {
	      appKey:this.state.appKey,
	      token:this.state.token,
	      connectionMetadata:this.state.connectionMetadata,
	      clusterUrl:this.state.clusterUrl
	    });
	  },
	
	
	  componentWillUnmount: function() {
	    RCTRealtimeMessaging.RTDisconnect();
	  },
	
	  doDisconnect:function(){
	      RCTRealtimeMessaging.RTDisconnect();
	  },
	
	  doSubscribe: function(){
	    RCTRealtimeMessaging.RTSubscribe(this.state.channel, true);
	  },
	
	  doUnSubscribe: function(){
	    RCTRealtimeMessaging.RTUnsubscribe(this.state.channel);
	  },
	
	  doSendMessage: function(){
	    RCTRealtimeMessaging.RTSendMessage(this.state.message, this.state.channel);
	  },
	
	  doPresence: function(){
	    RCTRealtimeMessaging.RTPresence(
	       this.state.clusterUrl,
	       true,
	       this.state.appKey,
	       this.state.token, 
	       this.state.channel
	     );
	  },
	
	  doSegue: function(){
	    this.props.navigator.push({
	      title: NavigatorIOSExample.title,
	      component: EmptyPage,
	      rightButtonTitle: 'Cancel',
	      onRightButtonPress: () => this.props.navigator.pop(),
	      passProps: {
	        text: 'This page has a right button in the nav bar',
	      }
	    });
	  },
	
	  _onException: function(exceptionEvent){
	    this._log("Exception:" + exceptionEvent.error);
	  },
	
	  _onConnected: function()
	  {
	    this._log("connected");
	  },
	
	
	  _onDisconnected: function(){
	    this._log("disconnected");
	  },
	
	  _onSubscribed: function(subscribedEvent)
	  {
	    this._log("subscribed channel " + subscribedEvent.channel);
	  },
	
	  _onUnSubscribed: function(unSubscribedEvent)
	  {
	    this._log("unsubscribed channel " + unSubscribedEvent.channel);
	  },
	
	  _onMessage: function(messageEvent)
	  { 
	    this._log("received message: ["+messageEvent.message+"] on channel [" + messageEvent.channel+"]");  
	  },
	  
	  _onPresence: function(presenceEvent){
	    if (presenceEvent.error) {
	      this._log("Error getting presence: " + presenceEvent.error);
	    }else
	    {
	      this._log("Presence data: " + JSON.stringify(presenceEvent.result));
	    };    
	  },
	
	
	  getInitialState: function() {
	    return {
	      clusterUrl: "http://ortc-developers.realtime.co/server/2.1/",
	      token: "SomeAuthenticatedToken",
	      appKey: "YOUR_APP_KEY",
	      channel: "yellow",
	      connectionMetadata: "clientConnMeta",
	      message: "some message",
	      dataSource: new ListView.DataSource({
	        rowHasChanged: (row1, row2) => row1 !== row2,
	      }),
	    };
	  },
	
	  _renderRow: function(rowData: string, sectionID: number, rowID: number) {
	    return (
	      <TouchableHighlight>
	        <View>
	          <View style={styles.row}>
	            <Text style={styles.text}>
	              {rowData}
	            </Text>
	          </View>
	          <View style={styles.separator} />
	        </View>
	      </TouchableHighlight>
	    );
	  },
	
	  _log: function(message: string)
	  {
	    var time = this.getFormattedDate();
	    time += " - " + message
	    var temp = [];
	    temp[0] = time;
	
	    for (var i = 0; i < messages.length; i++) {
	      temp[i+1] =  messages[i];
	    };
	    messages = temp;
	
	    this.setState({
	      dataSource: this.getDataSource(messages)
	    });
	  },
	
	  getFormattedDate: function() {
	    var date = new Date();
	    var str = date.getHours() + ":" + date.getMinutes() + ":" + date.getSeconds();
	    return str;
	  },
	
	  getDataSource: function(messages: Array<any>): ListView.DataSource {
	    return this.state.dataSource.cloneWithRows(messages);
	  },
	
	  render: function() {
	    return (
	      <ScrollView style={styles.container}>
	
	        <Text clusterUrl = {this.state.clusterUrl} >
	            clusterUrl:
	        </Text>
	        <TextInput
	          style={styles.textInput}
	          placeholder={this.state.clusterUrl}
	          onChangeText={(text) => this.setState({server: text})}
	        />
	
	        <View style={styles.custom}>
	          <View style={styles.margin}>
	            <Text server = {this.state.server} >
	                Authentication Token:
	            </Text>
	            <TextInput
	              style={styles.halfTextInput}
	              placeholder={this.state.token}
	              onChangeText={(text) => this.setState({token: text})}
	            />
	     
	            <Text server = {this.state.server} >
	                Application Key:
	            </Text>
	            <TextInput
	              style={styles.halfTextInput}
	              placeholder={this.state.appKey}
	              onChangeText={(text) => this.setState({appKey: text})}
	            />
	          </View>
	
	          <View style={styles.margin}>
	            <Text server = {this.state.server} >
	                Channel:
	            </Text>
	            <TextInput
	              style={styles.halfTextInput}
	              placeholder={this.state.channel}
	              onChangeText={(text) => this.setState({channel: text})}
	            />
	          
	            <Text server = {this.state.server} >
	                Connection Metadata:
	            </Text>
	            <TextInput
	              style={styles.halfTextInput}
	              placeholder={this.state.connectionMetadata}
	              onChangeText={(text) => this.setState({connectionMetadata: text})}
	            />
	          </View>
	
	        </View>
	        <Text server = {this.state.server} >
	            Message:
	        </Text>
	        <TextInput
	          style={styles.textInput}
	          placeholder={this.state.message}
	          onChangeText={(text) => this.setState({message: text})}
	        />
	
	
	        <View style={styles.rowView}>
	
	          <TouchableHighlight style={styles.button} onPress={this.doConnect}>
	            <View style={styles.tryAgain}>
	              <Text style={styles.tryAgainText}>Connect</Text>
	            </View>
	          </TouchableHighlight>
	
	          <TouchableHighlight style={styles.button} onPress={this.doDisconnect}>
	            <View style={styles.tryAgain}>
	              <Text style={styles.tryAgainText}>Disconnect</Text>
	            </View>
	          </TouchableHighlight>
	
	          <TouchableHighlight style={styles.button} onPress={this.doSubscribe}>
	            <View style={styles.tryAgain}>
	              <Text style={styles.tryAgainText}>Subscribe</Text>
	            </View>
	          </TouchableHighlight>
	
	          <TouchableHighlight style={styles.button} onPress={this.doUnSubscribe}>
	            <View style={styles.tryAgain}>
	              <Text style={styles.tryAgainText}>Unsubscribe</Text>
	            </View>
	          </TouchableHighlight>
	
	          <TouchableHighlight style={styles.button} onPress={this.doSendMessage}>
	            <View style={styles.tryAgain}>
	              <Text style={styles.tryAgainText}>Send</Text>
	            </View>
	          </TouchableHighlight>
	
	          <TouchableHighlight style={styles.button} onPress={this.doPresence}>
	            <View style={styles.tryAgain}>
	              <Text style={styles.tryAgainText}>Presence</Text>
	            </View>
	          </TouchableHighlight>
	
	        </View>
	        <ListView
	          style={styles.list}
	          dataSource={this.state.dataSource}
	          renderRow={this._renderRow}
	        />
	      </ScrollView>
	
	    )}
	  });
	
	var styles = StyleSheet.create({
	  container: {
	    marginTop: 30,
	    margin: 5,
	    backgroundColor: '#FFFFFF',
	  },
	  list: {
	    flexDirection: 'column',
	    backgroundColor: '#F6F6F6',
	    height:150,
	  },
	  rowView:{
	    alignItems: 'stretch',
	    flexDirection: 'row',
	    flexWrap: 'wrap',
	    justifyContent:'center',
	  },
	  button:{
	    margin: 5,
	  },
	  margin:{
	    
	  },
	  custom:{
	    flexDirection: 'row',
	    flexWrap: 'wrap',
	    justifyContent:'space-between',
	  },
	  textInput:{
	    height: 30,
	    borderColor: 'gray',
	    borderWidth: 1,
	    borderRadius: 4,
	    padding: 5,
	    fontSize: 15,
	  },
	
	  halfTextInput:{
	    height: 30,
	    borderColor: 'gray',
	    borderWidth: 1,
	    borderRadius: 4,
	    padding: 5,
	    fontSize: 15,
	    width: 153,
	  },
	  tryAgain: {
	    backgroundColor: '#336699',
	    padding: 13,
	    borderRadius: 5,
	  },
	  tryAgainText: {
	    color: '#ffffff',
	    fontSize: 14,
	    fontWeight: '500',
	  },
	  welcome: {
	    fontSize: 20,
	    textAlign: 'center',
	    margin: 10,
	  },
	  instructions: {
	    textAlign: 'center',
	    color: '#333333',
	  },
	  row: {
	    flexDirection: 'row',
	    justifyContent: 'center',
	    padding: 10,
	    backgroundColor: '#F6F6F6',
	  },
	  separator: {
	    height: 1,
	    backgroundColor: '#CCCCCC',
	  },
	  thumb: {
	    width: 64,
	    height: 64,
	  },
	  text: {
	    flex: 1,
	    fontSize: 13,
	  },
	});
	
	AppRegistry.registerComponent('RealtimeRCT', () => RealtimeRCT);

	
## Authors
Realtime.co
	
	
	


