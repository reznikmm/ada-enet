-----------------------------------------------------------------------
--  net-ntp -- NTP Network utilities
--  Copyright (C) 2017 Stephane Carrez
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
--  with Interfaces;  use Interfaces;
with Net.Headers;

package body Net.NTP is

   --  ------------------------------
   --  Get the NTP client status.
   --  ------------------------------
   function Get_Status (Request : in Client) return Status_Type is
   begin
      return Request.State.Get_Status;
   end Get_Status;

   --  ------------------------------
   --  Get the NTP time.
   --  ------------------------------
   function Get_Time (Request : in out Client) return NTP_Timestamp is
      Result : NTP_Timestamp;
      Clock  : Ada.Real_Time.Time;
   begin
      Request.State.Get_Timestamp (Result, Clock);
      return Result;
   end Get_Time;

   --  ------------------------------
   --  Get the delta time between the NTP server and us.
   --  ------------------------------
   function Get_Delta (Request : in out Client) return Integer_64 is
   begin
      return Request.State.Get_Delta;
   end Get_Delta;

   --  ------------------------------
   --  Initialize the NTP client to use the given NTP server.
   --  ------------------------------
   procedure Initialize (Request : access Client;
                         Ifnet   : access Net.Interfaces.Ifnet_Type'Class;
                         Server  : in Net.Ip_Addr) is
      Addr : Net.Sockets.Sockaddr_In;
   begin
      Request.Server := Server;
      Addr.Port := Net.Headers.To_Network (NTP_PORT);
      Addr.Addr := Ifnet.Ip;
      Request.Bind (Ifnet => Ifnet,
                    Addr  => Addr);
   end Initialize;

   --  ------------------------------
   --  Process the NTP client.
   --  Return in <tt>Next_Call</tt> the maximum time to wait before the next call.
   --  ------------------------------
   procedure Process (Request   : in out Client;
                      Next_Call : out Ada.Real_Time.Time_Span) is
      use type Ada.Real_Time.Time;

      Buf    : Net.Buffers.Buffer_Type;
      Status : Error_Code;
      To     : Net.Sockets.Sockaddr_In;
      Now    : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
   begin
      if Now < Request.Deadline then
         Next_Call := Request.Deadline - Now;
         return;
      end if;
      Request.Deadline := Now + Ada.Real_Time.Seconds (8);
      Next_Call := Ada.Real_Time.Seconds (8);
      Net.Buffers.Allocate (Buf);
      Buf.Set_Type (Net.Buffers.UDP_PACKET);

      --  NTP flags: clock unsynchronized, NTP version 4, Mode client.
      Buf.Put_Uint8 (16#e3#);

      --  Peer clock stratum: 0 for the client.
      Buf.Put_Uint8 (0);

      --  Peer polling interval: 6 = 64 seconds.
      Buf.Put_Uint8 (16#6#);

      --  Peer clock precision: 0 sec.
      Buf.Put_Uint8 (16#e9#);

      --  Root delay
      Buf.Put_Uint32 (0);

      --  Root dispersion
      Buf.Put_Uint32 (0);
      Buf.Put_Uint8 (16#49#);
      Buf.Put_Uint8 (16#4e#);
      Buf.Put_Uint8 (16#49#);
      Buf.Put_Uint8 (16#54#);
      Request.State.Put_Timestamp (Buf);

      To.Port := Net.Headers.To_Network (NTP_PORT);
      To.Addr := Request.Server;
      Request.Send (To, Buf, Status);
   end Process;

   --  ------------------------------
   --  Receive the NTP response from the NTP server and update the NTP state machine.
   --  ------------------------------
   overriding
   procedure Receive (Request  : in out Client;
                      From     : in Net.Sockets.Sockaddr_In;
                      Packet   : in out Net.Buffers.Buffer_Type) is
      pragma Unreferenced (From);

      Stratum    : Net.Uint8;
      Interval   : Net.Uint8;
      Precision  : Net.Uint8;
      Root_Delay : Net.Uint32;
      Dispersion : Net.Uint32;
      Ref_Id     : Net.Uint32;
      pragma Unreferenced (Stratum, Interval, Precision, Root_Delay, Dispersion, Ref_Id);
   begin
      if Packet.Get_Length < 56 or else Packet.Get_Uint8 /= 16#24# then
         return;
      end if;
      Stratum    := Packet.Get_Uint8;
      Interval   := Packet.Get_Uint8;
      Precision  := Packet.Get_Uint8;
      Root_Delay := Packet.Get_Uint32;
      Dispersion := Packet.Get_Uint32;
      Ref_Id     := Packet.Get_Uint32;
      Request.State.Extract_Timestamp (Packet);
   end Receive;

   ONE_SEC  : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Seconds (1);
   ONE_USEC : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Microseconds (1);

   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;
   function To_Unsigned_64 (T : in NTP_Timestamp) return Unsigned_64;
   function "-" (Left, Right : in NTP_Timestamp) return Integer_64;

   function To_Unsigned_64 (T : in NTP_Timestamp) return Unsigned_64 is
   begin
      return Unsigned_64 (T.Sub_Seconds)
        + Shift_Left (Unsigned_64 (T.Seconds), 32);
   end To_Unsigned_64;

   function "-" (Left, Right : in NTP_Timestamp) return Integer_64 is
      T1 : constant Unsigned_64 := To_Unsigned_64 (Left);
      T2 : constant Unsigned_64 := To_Unsigned_64 (Right);
   begin
      if T1 > T2 then
         return Integer_64 (T1 - T2);
      else
         return -Integer_64 (T2 - T2);
      end if;
   end "-";

   protected body Machine is

      --  ------------------------------
      --  Get the NTP status.
      --  ------------------------------
      function Get_Status return Status_Type is
      begin
         return Status;
      end Get_Status;

      --  Get the delta time between the NTP server and us.
      function Get_Delta return Integer_64 is
      begin
         return Delta_Time;
      end Get_Delta;

      --  ------------------------------
      --  Get the current NTP timestamp with the corresponding monitonic time.
      --  ------------------------------
      procedure Get_Timestamp (Time : out NTP_Timestamp;
                               Now  : out Ada.Real_Time.Time) is

         Dt     : Ada.Real_Time.Time_Span;
         Sec    : Integer;
         Usec   : Integer;
         N      : Unsigned_64;
      begin
         Now  := Ada.Real_Time.Clock;
         Dt   := Now - Offset_Ref;
         Sec  := Dt / ONE_SEC;
         Time.Seconds := Offset_Time.Seconds + Net.Uint32 (Sec);
         Usec := (Dt - Ada.Real_Time.Seconds (Sec)) / ONE_USEC;
         N    := Shift_Left (Unsigned_64 (Usec), 32);
         N    := N / 1_000_000;
         if Offset_Time.Sub_Seconds > Net.Uint32'Last - Net.Uint32 (N) then
            Time.Sub_Seconds := Offset_Time.Sub_Seconds - Net.Uint32 (N);
            Time.Seconds := Time.Seconds + 1;
         else
            Time.Sub_Seconds := Offset_Time.Sub_Seconds + Net.Uint32 (N);
         end if;
      end Get_Timestamp;

      --  ------------------------------
      --  Insert in the packet the timestamp references for the NTP client packet.
      --  ------------------------------
      procedure Put_Timestamp (Buf : in out Net.Buffers.Buffer_Type) is
         Now   : NTP_Timestamp;
         Clock : Ada.Real_Time.Time;
      begin
         Buf.Put_Uint32 (0);
         Buf.Put_Uint32 (0);
         Buf.Put_Uint32 (Orig_Time.Seconds);
         Buf.Put_Uint32 (Orig_Time.Sub_Seconds);
         Buf.Put_Uint32 (Rec_Time.Seconds);
         Buf.Put_Uint32 (Rec_Time.Sub_Seconds);
         Get_Timestamp (Now, Clock);
         Buf.Put_Uint32 (Now.Seconds);
         Buf.Put_Uint32 (Now.Sub_Seconds);
         Transmit_Time := Now;
      end Put_Timestamp;

      --  ------------------------------
      --  Extract the timestamp from the NTP server response and update the reference time.
      --  ------------------------------
      procedure Extract_Timestamp (Buf : in out Net.Buffers.Buffer_Type) is
         OTime : NTP_Timestamp;
         RTime : NTP_Timestamp;
         Now   : NTP_Timestamp;
         Rec   : NTP_Timestamp;
         Clock : Ada.Real_Time.Time;
         pragma Unreferenced (RTime);
      begin
         Get_Timestamp (Now, Clock);
         RTime.Seconds     := Buf.Get_Uint32;
         RTime.Sub_Seconds := Buf.Get_Uint32;
         OTime.Seconds     := Buf.Get_Uint32;
         OTime.Sub_Seconds := Buf.Get_Uint32;

         --  Check for bogus packet (RFC 5905, 8.  On-Wire Protocol).
         if OTime /= Transmit_Time then
            return;
         end if;
         Transmit_Time.Seconds     := 0;
         Transmit_Time.Sub_Seconds := 0;
         Rec.Seconds       := Buf.Get_Uint32;
         Rec.Sub_Seconds   := Buf.Get_Uint32;
         Orig_Time.Seconds := Buf.Get_Uint32;
         Orig_Time.Sub_Seconds := Buf.Get_Uint32;
         Rec_Time  := Now;
         Offset_Time := Orig_Time;
         Offset_Ref  := Clock;

         --  (T4 - T1) - (T3 - T2)
         Delta_Time := (Rec_Time - OTime) - (Orig_Time - Rec);
         if Delta_Time < 0 then
            Delta_Time := 0;
         end if;
      end Extract_Timestamp;

   end Machine;

end Net.NTP;
