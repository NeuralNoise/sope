/*
  Copyright (C) 2000-2007 SKYRIX Software AG
  Copyright (C) 2007      Helge Hess

  This file is part of SOPE.

  SOPE is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.

  SOPE is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with SOPE; see the file COPYING.  If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSArray.h>

#include <ldap.h>

#include "NSString+DN.h"
#include <NGExtensions/NSString+Ext.h>
#include "common.h"

static NSString *dnSeparator = @",";

static NSCharacterSet *escapableChars = nil;

static NSArray *cleanDNComponents(NSArray *_components) {
  unsigned i, count;
  id *cs;
  
  if ((count = [_components count]) == 0)
    return nil;
  
  cs = calloc(count, sizeof(id));
  
  for (i = 0; i < count; i++)
    cs[i] = [[_components objectAtIndex:i] stringByTrimmingWhiteSpaces];
  
  _components = [NSArray arrayWithObjects:cs count:count];
  if (cs != NULL) { free(cs); cs = NULL; }
  
  return _components;
}

@implementation NSString(DNSupport)

+ (NSString *)dnWithComponents:(NSArray *)_components {
  return [cleanDNComponents(_components) componentsJoinedByString:dnSeparator];
}

/* returns each dn component in a NSArray 
 * returns nil if there is a decoding error
 */
- (NSArray *)dnComponents {
  char *componentStr;
  int i, err;

  LDAPDN dn;

  NSMutableArray *components;

  if (![self length])
    return nil;

  dn = NULL;
  components = [NSMutableArray arrayWithCapacity:0];

  err = ldap_str2dn([self cStringUsingEncoding: NSUTF8StringEncoding],
                    &dn, LDAP_DN_FORMAT_LDAPV3);
  if(err) {
    /* sorry for the noise but this has to be known */
    NSLog(@"ldap_str2dn: %s\n", ldap_err2string(err));
    ldap_dnfree(dn);
    return nil;
  }
    
  /* loop through the dn parts
   * convert them back to properly quoted/escaped strings 
   */
  for (i=0; dn[i]; i++) {
    componentStr = NULL;
    err = ldap_rdn2str(dn[i], &componentStr,
                       LDAP_DN_FORMAT_LDAPV3 | LDAP_DN_PRETTY);
    if(err) {
      NSLog(@"ldap_rdn2dn: %s\n", ldap_err2string(err));
      ldap_dnfree(dn);
      return nil;
    }

    if(componentStr) {
      [components addObject:
                    [NSString stringWithCString: componentStr
                                       encoding: NSUTF8StringEncoding]];
      free(componentStr);
    }
  }

  ldap_dnfree(dn);
  return [NSArray arrayWithArray: components];
}

- (NSString *)stringByAppendingDNComponent:(NSString *)_component {
  NSString *s;

  if (![(s = [self stringByTrimmingWhiteSpaces]) isNotEmpty])
    return _component;
  
  s = [dnSeparator stringByAppendingString:self];
  return [_component stringByAppendingString:s];
}

- (NSString *)stringByDeletingLastDNComponent {
  NSMutableArray *components;

  components = [NSMutableArray arrayWithArray: [self dnComponents]];
  if (![components count])
    return nil;

  /* "Last DN component" is actually the first component :
   * For "cn=bob,ou=users,dc=example,dc=com", remove "cn=bob"
   */
  [components removeObjectAtIndex: 0];

  return [components componentsJoinedByString:dnSeparator];
}

- (NSString *)lastDNComponent {
  NSMutableArray *components;

  components = [NSMutableArray arrayWithArray: [self dnComponents]];
  if (![components count])
    return nil;

  /* "Last DN component" is actually the first component :
   * For "cn=bob,ou=users,dc=example,dc=com", return "cn=bob"
   */
  return [components objectAtIndex: 0];
}

- (const char *)ldapRepresentation {
  return [self UTF8String];
}

- (NSDate *)ldapTimestamp {
  /* eg: '20000403055250Z' */
  unsigned   len;
  short      year, month, day, hour, minute, second;
  NSString   *tzname;
  NSTimeZone *tz;
  
  if ((len = [self length]) == 0)
    return nil;

  if (len < 14)
    return nil;
  
  year   = [[self substringWithRange:NSMakeRange(0,  4)] intValue];
  month  = [[self substringWithRange:NSMakeRange(4,  2)] intValue];
  day    = [[self substringWithRange:NSMakeRange(6,  2)] intValue];
  hour   = [[self substringWithRange:NSMakeRange(8,  2)] intValue];
  minute = [[self substringWithRange:NSMakeRange(10, 2)] intValue];
  second = [[self substringWithRange:NSMakeRange(12, 2)] intValue];

  /* timezone ??? */
  tzname = @"GMT";
  tz = [NSTimeZone timeZoneWithAbbreviation:tzname];

  return [NSCalendarDate dateWithYear:year month:month
                         day:day hour:hour minute:minute second:second
                         timeZone:tz];
}

- (NSString *) escapedForLDAPDN
{
  NSMutableString *newString;
  NSString *format;
  unichar *uniString;
  unichar currentChar;
  NSUInteger count, length;

  if (!escapableChars)
    {
      escapableChars = [NSCharacterSet
                         characterSetWithCharactersInString: @"\"+,;<>\\"];
      [escapableChars retain];
    }

  length = [self length];
  newString = [NSMutableString stringWithCapacity: length];

  uniString = NSZoneMalloc (NULL, sizeof (unichar) * length);
  [self getCharacters: uniString];

  /* see rfc4514, section 2.4 */
  for (count = 0; count < length; count++)
    {
      currentChar = uniString[count];
      if ((currentChar == ' ' && (count == 0 || count == (length - 1)))
          || [escapableChars characterIsMember: currentChar])
        format = @"\\%Lc";
      else
        format = @"%Lc";
      [newString appendFormat: format, currentChar];
    }

  NSZoneFree (NULL, uniString);

  return newString;
}

@end /* NSString(DNSupport) */
