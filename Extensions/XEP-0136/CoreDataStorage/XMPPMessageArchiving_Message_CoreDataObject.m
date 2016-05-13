#import "XMPPMessageArchiving_Message_CoreDataObject.h"
#import "XMPPMessageArchivingCoreDataStorage.h"
#import "XMPPLogging.h"

#if DEBUG
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN; // | XMPP_LOG_FLAG_TRACE;
#else
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif


@interface XMPPMessageArchiving_Message_CoreDataObject ()

@property(nonatomic,strong) XMPPMessage * primitiveMessage;
@property(nonatomic,strong) NSString * primitiveMessageStr;

@property(nonatomic,strong) XMPPJID * primitiveBareJid;
@property(nonatomic,strong) NSString * primitiveBareJidStr;

@end

@implementation XMPPMessageArchiving_Message_CoreDataObject

@dynamic message, primitiveMessage;
@dynamic messageStr, primitiveMessageStr;
@dynamic bareJid, primitiveBareJid;
@dynamic bareJidStr, primitiveBareJidStr;
@dynamic body;
@dynamic thread;
@dynamic outgoing;
@dynamic composing;
@dynamic timestamp;
@dynamic streamBareJidStr;

#pragma mark Transient message

- (XMPPMessage *)message
{
	// Create and cache on demand
	
	[self willAccessValueForKey:@"message"];
	XMPPMessage *message = self.primitiveMessage;
	[self didAccessValueForKey:@"message"];
	
	if (message == nil)
	{
		NSString *messageStr = self.messageStr;
		if (messageStr)
		{
			NSXMLElement *element = [[NSXMLElement alloc] initWithXMLString:messageStr error:nil];
			message = [XMPPMessage messageFromElement:element];
			self.primitiveMessage = message;
		}
    }
	
    return message;
}

- (void)setMessage:(XMPPMessage *)message
{
	[self willChangeValueForKey:@"message"];
	[self willChangeValueForKey:@"messageStr"];
	
	self.primitiveMessage = message;
	self.primitiveMessageStr = [message compactXMLString];
	
	[self didChangeValueForKey:@"message"];
	[self didChangeValueForKey:@"messageStr"];
}

- (void)setMessageStr:(NSString *)messageStr
{
	[self willChangeValueForKey:@"message"];
	[self willChangeValueForKey:@"messageStr"];
	
	NSXMLElement *element = [[NSXMLElement alloc] initWithXMLString:messageStr error:nil];
	self.primitiveMessage = [XMPPMessage messageFromElement:element];
	self.primitiveMessageStr = messageStr;
	
	[self didChangeValueForKey:@"message"];
	[self didChangeValueForKey:@"messageStr"];
}

#pragma mark Transient bareJid

- (XMPPJID *)bareJid
{
	// Create and cache on demand
	
	[self willAccessValueForKey:@"bareJid"];
	XMPPJID *tmp = self.primitiveBareJid;
	[self didAccessValueForKey:@"bareJid"];
	
	if (tmp == nil)
	{
		NSString *bareJidStr = self.bareJidStr;
		if (bareJidStr)
		{
			tmp = [XMPPJID jidWithString:bareJidStr];
			self.primitiveBareJid = tmp;
		}
	}
	
	return tmp;
}

- (void)setBareJid:(XMPPJID *)bareJid
{
	if ([self.bareJid isEqualToJID:bareJid options:XMPPJIDCompareBare])
	{
		return; // No change
	}
	
	[self willChangeValueForKey:@"bareJid"];
	[self willChangeValueForKey:@"bareJidStr"];
	
	self.primitiveBareJid = [bareJid bareJID];
	self.primitiveBareJidStr = [bareJid bare];
	
	[self didChangeValueForKey:@"bareJid"];
	[self didChangeValueForKey:@"bareJidStr"];
}

- (void)setBareJidStr:(NSString *)bareJidStr
{
	if ([self.bareJidStr isEqualToString:bareJidStr])
	{
		return; // No change
	}
	
	[self willChangeValueForKey:@"bareJid"];
	[self willChangeValueForKey:@"bareJidStr"];
	
	XMPPJID *bareJid = [[XMPPJID jidWithString:bareJidStr] bareJID];
	
	self.primitiveBareJid = bareJid;
	self.primitiveBareJidStr = [bareJid bare];
	
	[self didChangeValueForKey:@"bareJid"];
	[self didChangeValueForKey:@"bareJidStr"];
}

#pragma mark Convenience properties

- (BOOL)isOutgoing
{
	return [self.outgoing boolValue];
}

- (void)setIsOutgoing:(BOOL)flag
{
	self.outgoing = @(flag);
}

- (BOOL)isComposing
{
	return [self.composing boolValue];
}

- (void)setIsComposing:(BOOL)flag
{
	self.composing = @(flag);
}

+ (void)removeMessageAndUpdateContactMessage:(XMPPMessageArchiving_Message_CoreDataObject *)message inMangedObjectContext:(NSManagedObjectContext *)context{
    [context deleteObject:message];
    XMPPJID *jid = message.bareJid;
    
    NSFetchRequest *request = [[NSFetchRequest alloc]initWithEntityName:@"XMPPMessageArchiving_Message_CoreDataObject"];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"bareJidStr == %@ AND streamBareJidStr == %@",message.bareJidStr,message.streamBareJidStr];
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO];
    
    [request setPredicate:predicate];
    [request setSortDescriptors:@[sort]];
    [request setFetchLimit:1];
    
    NSArray *result = [context executeFetchRequest:request error:nil];

    
    XMPPMessageArchiving_Message_CoreDataObject *nextMessage = nil;
    if ([result count] >= 1) {
        nextMessage = [result objectAtIndex:0];
    }
    
    XMPPMessageArchiving_Contact_CoreDataObject *contactMessage = [[XMPPMessageArchivingCoreDataStorage sharedInstance] contactWithBareJidStr:message.bareJidStr streamBareJidStr:message.streamBareJidStr managedObjectContext:context];
    contactMessage.mostRecentMessageBody = nextMessage.message.body;
    contactMessage.mostRecentMessageOutgoing = nextMessage.outgoing;
    contactMessage.mostRecentMessageTimestamp = nextMessage.timestamp;
    
    NSError *error = nil;
    [context save:&error];
    if (error) {
        XMPPLogError(@"%@: %@ - Unable to save!", THIS_FILE, THIS_METHOD);
    }
}

+ (void)removeMessagesAndUpdateContactMessage:(NSArray *)messages inMangedObjectContext:(NSManagedObjectContext *)context{
    
    NSString *streamJIDStr = ((XMPPMessageArchiving_Message_CoreDataObject *)[messages firstObject]).streamBareJidStr;
    NSMutableDictionary *dicOfSameJidMessageArray = [NSMutableDictionary dictionary];
    [messages enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        XMPPMessageArchiving_Message_CoreDataObject *message = (XMPPMessageArchiving_Message_CoreDataObject *)obj;
        XMPPJID *bareJid = message.bareJid;
        if (dicOfSameJidMessageArray.count<=0 || ![dicOfSameJidMessageArray.allKeys containsObject:bareJid]) {
            [dicOfSameJidMessageArray setObject:[NSMutableArray arrayWithObject:message] forKey:bareJid];
        }else{
            NSMutableArray *messArr = [dicOfSameJidMessageArray objectForKey:bareJid];
            [messArr addObject:message];
        }
        
    }];//先将message数组转化为相同jid的数组组成的字典对象
    
    
    [dicOfSameJidMessageArray enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        XMPPJID *jid = (XMPPJID *)key;
        NSMutableArray *messageArr = (NSMutableArray *)obj;
        for (XMPPMessageArchiving_Message_CoreDataObject *message in messageArr) {
            [context deleteObject:message];
        }
        
        NSFetchRequest *request = [[NSFetchRequest alloc]initWithEntityName:@"XMPPMessageArchiving_Message_CoreDataObject"];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"bareJidStr == %@ AND streamBareJidStr == %@",jid.bare,streamJIDStr];
        NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO];
        
        [request setPredicate:predicate];
        [request setSortDescriptors:@[sort]];
        [request setFetchLimit:1];
        
        NSArray *result = [context executeFetchRequest:request error:nil];
        
        XMPPMessageArchiving_Message_CoreDataObject *nextMessage = nil;
        if ([result count] >= 1) {
            nextMessage = [result objectAtIndex:0];
        }
        
        XMPPMessageArchiving_Contact_CoreDataObject *contactMessage = [[XMPPMessageArchivingCoreDataStorage sharedInstance] contactWithBareJidStr:jid.bare streamBareJidStr:streamJIDStr managedObjectContext:context];
        contactMessage.mostRecentMessageBody = nextMessage.message.body;
        contactMessage.mostRecentMessageOutgoing = nextMessage.outgoing;
        contactMessage.mostRecentMessageTimestamp = nextMessage.timestamp;
    }];
    

    NSError *error = nil;
    [context save:&error];
    if (error) {
        XMPPLogError(@"%@: %@ - Unable to save!", THIS_FILE, THIS_METHOD);
    }
}

#pragma mark Hooks

- (void)willInsertObject
{
	// If you extend XMPPMessageArchiving_Message_CoreDataObject,
	// you can override this method to use as a hook to set your own custom properties.
}

- (void)didUpdateObject
{
	// If you extend XMPPMessageArchiving_Message_CoreDataObject,
	// you can override this method to use as a hook to set your own custom properties.
}

@end
