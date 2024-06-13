-----------------------------------------------------------------------
--  net-utils -- Network utilities
--  Copyright (C) 2016, 2017 Stephane Carrez
--  Written by Stephane Carrez (Stephane.Carrez@gmail.com)
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
-----------------------------------------------------------------------
package Net.Utils is

   --  Convert the IPv4 address to a dot string representation.
   function To_String (Ip : in Ip_Addr) return String;

   --  Convert the Ethernet address to a string representation.
   function To_String (Mac : in Ether_Addr) return String;

   --  Get a 32-bit random number.
   function Random return Uint32;

   type Custom_Random_Function is not null access function return Uint32;

   procedure Set_Random_Function (Value : Custom_Random_Function);
   --  Provide alternative random number generation function.

private

   function Default_Random return Uint32;

   Random_Function : Custom_Random_Function :=
     Default_Random'Access;

   function Random return Uint32 is (Random_Function.all);

end Net.Utils;
