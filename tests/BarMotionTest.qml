import QtQuick
import QtQuick.Window
import QtTest
import "Plugin" as Lofi

Window {
  id: window
  width: 100; height: 60; visible: true
  Lofi.BarWidget { id: widget; x: 20; y: 10 }
  TestCase {
    name: "SkylofiBarMotion"
    when: true
    function apply(extra) {
      var value={running:true,paused:false,main_running:true,main_state:"playing",name:"Test radio",main_volume:65,master_volume:80,bg_running:false,bg_state:"stopped",bg_volume:30,nature_layers:[],animations:true,equalizer_animation:true}
      Object.assign(value,extra || {})
      widget.applyStatus(JSON.stringify(value))
    }
    function indicator() { return findChild(widget,"barPlaybackActivity") }
    function init() {
      window.visible=true
      widget.visible=true
      widget.statusReady=true
      apply()
    }
    function test_musicPlaybackRemainsOngoing() {
      verify(widget.playbackActive)
      compare(widget.playbackLabel,"Playing")
      var wave=indicator()
      verify(wave !== null)
      tryCompare(wave,"moving",true)
      var count=wave.frameCount
      wait(1100)
      verify(wave.moving)
      verify(wave.frameCount>count)
    }
    function test_pureConnectionRetryDoesNotPretendToPlay() {
      apply({main_state:"connecting"})
      compare(widget.playbackActive,false)
      compare(widget.playbackLabel,"Connecting")
      compare(indicator().moving,false)
      apply({main_state:"reconnecting",main_running:false})
      compare(widget.playbackActive,false)
      compare(widget.playbackLabel,"Reconnecting")
      compare(indicator().moving,false)
      apply({main_state:"reconnecting",main_running:false,master_volume:0})
      compare(widget.playbackLabel,"Reconnecting")
    }
    function test_natureCanPlayWhileMusicHasEndedOrRetries() {
      var nature=[{enabled:true,running:true,volume:35}]
      apply({main_running:false,main_state:"ended",nature_layers:nature})
      compare(widget.playbackActive,true)
      compare(indicator().moving,true)
      apply({main_running:false,main_state:"reconnecting",nature_layers:nature})
      compare(widget.playbackActive,true)
      compare(indicator().moving,true)
      apply({main_running:false,main_state:"failed",nature_layers:[{enabled:true,running:true,volume:0}]})
      compare(widget.playbackActive,false)
      compare(widget.playbackLabel,"Muted")
      compare(indicator().moving,false)
      apply({main_running:false,main_state:"ended",nature_layers:[{enabled:true,running:true,volume:0}]})
      compare(widget.playbackLabel,"Muted")
    }
    function test_voiceMustActuallyPlayAtAnAudibleLevel() {
      apply({main_state:"connecting",bg_running:true,bg_state:"playing"})
      compare(widget.playbackActive,true)
      apply({main_state:"connecting",bg_running:false,bg_state:"loading"})
      compare(widget.playbackActive,false)
      compare(indicator().moving,false)
      apply({main_state:"connecting",bg_running:true,bg_state:"playing",bg_volume:0})
      compare(widget.playbackActive,false)
      compare(widget.playbackLabel,"Muted")
      compare(indicator().moving,false)
      apply({main_state:"ended",bg_running:true,bg_state:"playing",bg_volume:0})
      compare(widget.playbackLabel,"Muted")
    }
    function test_pauseStopFinishAndMasterMuteStopMotion() {
      for(var extra of [{paused:true},{running:false},{main_state:"ended"},{master_volume:0}]) {
        apply(extra)
        compare(widget.playbackActive,false)
        compare(indicator().moving,false)
      }
      apply({main_volume:0})
      compare(widget.playbackActive,false)
      compare(widget.playbackLabel,"Muted")
      compare(indicator().moving,false)
    }
    function test_preferencesLeaveStaticPlayingMark() {
      apply({animations:false})
      compare(widget.playbackActive,true)
      compare(indicator().visible,true)
      compare(indicator().moving,false)
      apply({equalizer_animation:false})
      compare(widget.playbackActive,true)
      compare(indicator().moving,false)
      apply()
      tryCompare(indicator(),"moving",true)
    }
    function test_hiddenBarStopsAndReturns() {
      var wave=indicator()
      tryCompare(wave,"moving",true)
      widget.visible=false
      compare(wave.moving,false)
      var count=wave.frameCount
      wait(300)
      compare(wave.frameCount,count)
      widget.visible=true
      tryCompare(wave,"moving",true)
      tryVerify(function(){return wave.frameCount>count})
    }
    function cleanupTestCase() {
      console.log("BAR_MOTION_TEST_RESULT",JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
