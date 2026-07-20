/*
 * Copyright (C) 2021-2024, 5DPLAY Game Studio
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

package {
import flash.display.Sprite;
import flash.display.StageDisplayState;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.events.UncaughtErrorEvent;
import flash.text.TextField;
import flash.text.TextFormat;
import flash.ui.Keyboard;

import net.play5d.game.bvn.GameQuality;
import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.ctrler.AssetManager;
import net.play5d.game.bvn.data.GameData;
import net.play5d.game.bvn.debug.Debugger;
import net.play5d.game.bvn.interfaces.GameInterface;
import net.play5d.game.bvn.ui.GameUI;
import net.play5d.game.bvn.ui.UIUtils;
import net.play5d.game.bvn.utils.GameLogger;
import net.play5d.game.bvn.utils.ResUtils;
import net.play5d.game.bvn.utils.URL;
import net.play5d.game.bvn.win.AssetLoader;
import net.play5d.game.bvn.win.GameInterfaceManager;
import net.play5d.game.bvn.win.MosouDebugger;
import net.play5d.game.bvn.win.SwfLib;
import net.play5d.game.bvn.win.utils.Loger;
import net.play5d.game.bvn.win.utils.UIAssetUtil;

[SWF(width='800', height='600', frameRate='30', backgroundColor='#000000')]
public class launch extends Sprite {
    public function launch() {
        if (stage) {
            initlize();
        }
        else {
            addEventListener(Event.ADDED_TO_STAGE, initlize);
        }
    }
    private var _mainGame:MainGame;
    private var _assetLoader:AssetLoader = new AssetLoader();
    private var _errorTf:TextField;

    private function safeFail(...param):void {
        trace('safe fail !');
    }

    private function buildGame():void {

        GameLogger.log('buildGame');

        _mainGame = new MainGame();
        //_mainGame.initlize(this , stage , initBackHandler , initFailHandler);
        _mainGame.initlize(this, stage, function ():void {
            GameLogger.log('ResUtils UI SWFs ready -> goLanguage');
            _mainGame.goLanguage(function ():void {
                GameLogger.log('language selected, font=' + FONT.fontName);
                trace('字体名称：' + FONT.fontName);
                UIUtils.LOCK_FONT = FONT.fontName;

                GameData.I.saveData();
                GameLogger.log('start initalizeLoad (GameLoadingStage)');
                _mainGame.initalizeLoad(initBackHandler, initFailHandler);
            });

        }, initFailHandler);
        if (Debugger.DEBUG_ENABLED) {
            Debugger.initDebug(stage);
        }

        stage.addEventListener(KeyboardEvent.KEY_DOWN, keyDownHandler);

    }

    private function initBackHandler():void {

        GameLogger.log('init ok -> UIAssetUtil / goLogo');

        UIAssetUtil.I.initalize(_mainGame.goLogo);
        //			_mainGame.goMenu();
        //			_mainGame.goCongratulations();
    }

    private function initFailHandler(msg:String):void {
        var text:String = 'init fail' + (msg ? (': ' + msg) : '');
        GameLogger.log(text);
        showFatal(text);
    }

    private function showFatal(msg:String):void {
        try {
            if (!_errorTf) {
                _errorTf                   = new TextField();
                _errorTf.width             = 780;
                _errorTf.height            = 580;
                _errorTf.x                 = 10;
                _errorTf.y                 = 10;
                _errorTf.multiline         = true;
                _errorTf.wordWrap          = true;
                _errorTf.selectable        = true;
                _errorTf.defaultTextFormat = new TextFormat('_sans', 14, 0xff4444);
                addChild(_errorTf);
            }
            _errorTf.text = msg +
                            '\n\nSee log.log under AIR applicationStorageDirectory' +
                            '\n(AppData\\Roaming\\...\\Local Store\\log.log)';
            setChildIndex(_errorTf, numChildren - 1);
        }
        catch (e:Error) {
            trace(e);
        }
    }

    private function onUncaughtError(e:UncaughtErrorEvent):void {
        e.preventDefault();
        var err:* = e.error;
        var msg:String;
        if (err is Error) {
            msg = Error(err).message + '\n' + Error(err).getStackTrace();
        }
        else {
            msg = String(err);
        }
        GameLogger.log('UNCAUGHT: ' + msg);
        showFatal('UNCAUGHT:\n' + msg);
    }

    private function initlize(e:Event = null):void {
        GameLogger.setLoger(new Loger());
        GameLogger.log('init...');

        removeEventListener(Event.ADDED_TO_STAGE, initlize);
        STAGE = stage;

        // Captive runtime: surface crashes that otherwise look like a black hang
        try {
            loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
            stage.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
        }
        catch (ue:Error) {
            GameLogger.log('uncaughtErrorEvents setup failed: ' + ue.message);
        }

        ResUtils.swfLib = new SwfLib();
        AssetManager.I.setAssetLoader(_assetLoader);

        GameInterface.instance = new GameInterfaceManager();

//			if(GameInterfaceManager.config.isFullScreen){
//				stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
//			}

        GameUI.BITMAP_UI = true;

        GameData.I.config.AI_level     = 1;
        GameData.I.config.quality      = GameQuality.LOW;
        GameData.I.config.keyInputMode = 1;

        URL.MARK = 'bvn_win' + MainGame.VERSION;

//			GameSafeKeeper.I.loadConfigure(buildGame, safeFail);
        buildGame();

        MosouDebugger.init(stage);
    }

    private function keyDownHandler(e:KeyboardEvent):void {
        if (e.keyCode == Keyboard.ESCAPE) {
            e.preventDefault();
        }
        if (e.keyCode == Keyboard.F11) {
            if (stage.displayState == StageDisplayState.NORMAL) {
                stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
            }
            else {
                stage.displayState = StageDisplayState.NORMAL;
            }
        }
    }

}
}
